import Foundation

struct BookLookupResult: Sendable {
    let title: String
    let author: String
    let isbn: String
    let genre: BookGenre
    let coverURL: String
}

struct BookLookupService {
    func lookup(barcode: String) async throws -> BookLookupResult? {
        let sanitized = barcode.filter(\.isNumber)
        guard !sanitized.isEmpty else { return nil }

        let isbnCandidates = normalizedISBNCandidates(from: sanitized)

        // Phase 1: Concurrent ISBN lookups (Google Books + Open Library in parallel)
        for candidate in isbnCandidates {
            if let result = await concurrentISBNLookup(isbn: candidate) {
                return await enrichAndValidateCover(result, isbnCandidates: isbnCandidates)
            }
        }

        // Phase 2: Broader search (Google Books + Open Library Search in parallel)
        let preferredISBN = isbnCandidates.first { $0.count == 10 || $0.count == 13 }
        async let googleSearch = bestEffort({ try await self.queryGoogleBooks(query: sanitized) })
        async let openLibSearch = bestEffort({ try await self.queryOpenLibrarySearch(query: sanitized, preferredISBN: preferredISBN) })

        let googleResult = await googleSearch
        let openLibResult = await openLibSearch

        if let result = googleResult {
            return await enrichAndValidateCover(result, isbnCandidates: isbnCandidates)
        }
        if let result = openLibResult {
            return await enrichAndValidateCover(result, isbnCandidates: isbnCandidates)
        }

        // Phase 3: WorldCat fallback
        for candidate in isbnCandidates where candidate.count == 10 || candidate.count == 13 {
            if let result = await bestEffort({ try await queryWorldCat(isbn: candidate) }) {
                return await enrichAndValidateCover(result, isbnCandidates: isbnCandidates)
            }
        }

        return nil
    }

    private func concurrentISBNLookup(isbn: String) async -> BookLookupResult? {
        let isValidLength = isbn.count == 10 || isbn.count == 13

        async let googleResult = bestEffort({ try await self.queryGoogleBooks(query: "isbn:\(isbn)") })
        async let openLibResult: BookLookupResult? = isValidLength
            ? await bestEffort({ try await self.queryOpenLibrary(isbn: isbn) })
            : nil

        // Prefer Google (richer metadata), fall back to Open Library
        if let google = await googleResult { return google }
        if let openLib = await openLibResult { return openLib }
        return nil
    }

    func lookupByTitle(query: String) async throws -> BookLookupResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        async let googleResult = bestEffort({ try await self.queryGoogleBooks(query: "intitle:\(trimmed)") })
        async let openLibResult = bestEffort({ try await self.queryOpenLibrarySearch(query: trimmed) })

        let google = await googleResult
        let openLib = await openLibResult

        if let result = google {
            return await enrichAndValidateCover(result, isbnCandidates: [])
        }
        if let result = openLib {
            return await enrichAndValidateCover(result, isbnCandidates: [])
        }

        return nil
    }

    func lookupCover(title: String, author: String, isbn: String) async throws -> String? {
        var candidates: [String] = []

        func appendCandidate(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if !candidates.contains(trimmed) {
                candidates.append(trimmed)
            }
        }

        let normalizedISBN = isbn.filter(\.isNumber)
        if normalizedISBN.count == 10 || normalizedISBN.count == 13 {
            if let byISBN = await bestEffort({ try await queryGoogleBooks(query: "isbn:\(normalizedISBN)") }) {
                appendCandidate(byISBN.coverURL)
            }

            if let byGoogleISBNSearch = await bestEffort({ try await queryGoogleCover(query: "isbn:\(normalizedISBN)") }) {
                appendCandidate(byGoogleISBNSearch)
            }

            appendCandidate("https://covers.openlibrary.org/b/isbn/\(normalizedISBN)-L.jpg?default=false")
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedTitle.isEmpty && !trimmedAuthor.isEmpty {
            if let exact = await bestEffort({ try await queryGoogleCover(query: "intitle:\(trimmedTitle) inauthor:\(trimmedAuthor)") }) {
                appendCandidate(exact)
            }
        }

        let broadQuery: String
        if !trimmedTitle.isEmpty && !trimmedAuthor.isEmpty {
            broadQuery = "\(trimmedTitle) \(trimmedAuthor)"
        } else if !trimmedTitle.isEmpty {
            broadQuery = "intitle:\(trimmedTitle)"
        } else if !trimmedAuthor.isEmpty {
            broadQuery = trimmedAuthor
        } else {
            return nil
        }

        if let broadResult = await bestEffort({ try await queryGoogleCover(query: broadQuery) }) {
            appendCandidate(broadResult)
        }

        if !trimmedTitle.isEmpty,
           let openLibraryCover = await bestEffort({ try await queryOpenLibraryCoverByMetadata(title: trimmedTitle, author: trimmedAuthor) }) {
            appendCandidate(openLibraryCover)
        }

        if let reachable = await bestEffort({ try await firstReachableCoverURL(from: candidates) }) {
            return reachable
        }

        return candidates.first
    }

    private func queryGoogleBooks(query: String) async throws -> BookLookupResult? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=\(encoded)&maxResults=10") else {
            return nil
        }

        let data = try await fetchData(from: url)
        let response = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
        guard let items = response.items, !items.isEmpty else { return nil }
        let validItems = items.filter { item in
            guard let title = item.volumeInfo.title?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !title.isEmpty
        }
        guard !validItems.isEmpty else { return nil }

        let numericQuery = query.filter(\.isNumber)
        let matchingISBNItems: [GoogleBookItem]
        if numericQuery.count == 10 || numericQuery.count == 13 {
            matchingISBNItems = validItems.filter { itemHasISBN($0, matching: numericQuery) }
        } else {
            matchingISBNItems = []
        }

        let prioritizedItems = matchingISBNItems.isEmpty ? validItems : matchingISBNItems
        let item = prioritizedItems.first { hasGoogleImageLinks($0.volumeInfo.imageLinks) } ?? prioritizedItems.first
        guard let item else { return nil }
        let volumeInfo = item.volumeInfo

        let title = volumeInfo.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let validTitle = title, !validTitle.isEmpty else { return nil }

        let authors = volumeInfo.authors
        let author = (authors?.first).map { String($0) } ?? "Unknown Author"

        let categories = volumeInfo.categories
        let category = (categories?.first).map { String($0) } ?? ""

        let mappedGenre = mapGenre(from: category)

        let identifiers = volumeInfo.industryIdentifiers
        let firstISBN = identifiers?.first(where: { ($0.type?.contains("ISBN")) == true })
        let isbn = firstISBN?.identifier ?? ((numericQuery.count == 10 || numericQuery.count == 13) ? numericQuery : "")

        let coverURL = normalizedGoogleImageURL(from: volumeInfo.imageLinks)

        return BookLookupResult(
            title: validTitle,
            author: author,
            isbn: isbn,
            genre: mappedGenre,
            coverURL: coverURL
        )
    }

    private func mapGenre(from category: String) -> BookGenre {
        let normalized = category.lowercased()

        if normalized.contains("fantasy") { return .fantasy }
        if normalized.contains("mystery") { return .mystery }
        if normalized.contains("thriller") { return .thriller }
        if normalized.contains("science") || normalized.contains("sci-fi") { return .scienceFiction }
        if normalized.contains("romance") { return .romance }
        if normalized.contains("history") { return .historical }
        if normalized.contains("biography") || normalized.contains("memoir") { return .biography }
        if normalized.contains("self") { return .selfHelp }
        if normalized.contains("juvenile") || normalized.contains("children") { return .children }
        if normalized.contains("fiction") { return .fiction }
        if normalized.contains("nonfiction") { return .nonFiction }

        return .other
    }

    private func hasGoogleImageLinks(_ links: GoogleBookImageLinks?) -> Bool {
        !normalizedGoogleImageURL(from: links).isEmpty
    }

    private func itemHasISBN(_ item: GoogleBookItem, matching target: String) -> Bool {
        guard target.count == 10 || target.count == 13 else { return false }
        guard let identifiers = item.volumeInfo.industryIdentifiers else { return false }
        return identifiers.contains { identifier in
            let normalized = identifier.identifier?.filter(\.isNumber) ?? ""
            return normalized == target
        }
    }

    private func normalizedGoogleImageURL(from links: GoogleBookImageLinks?) -> String {
        if let links {
            let candidates = [
                links.extraLarge,
                links.large,
                links.medium,
                links.small,
                links.thumbnail,
                links.smallThumbnail
            ]

            for candidate in candidates {
                guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                    continue
                }
                return value.replacingOccurrences(of: "http://", with: "https://")
            }
        }

        return ""
    }

    private func normalizedISBNCandidates(from rawDigits: String) -> [String] {
        var candidates: [String] = []

        func appendUnique(_ value: String) {
            guard !value.isEmpty, !candidates.contains(value) else { return }
            candidates.append(value)
        }

        appendUnique(rawDigits)

        // Some scanners return UPC-A for book codes; converting to EAN can help matching.
        if rawDigits.count == 12 {
            appendUnique("0" + rawDigits)
        }

        if let isbn13 = toISBN13(fromISBN10: rawDigits) {
            appendUnique(isbn13)
        }

        if let isbn10 = toISBN10(fromISBN13: rawDigits) {
            appendUnique(isbn10)
        }

        return candidates
    }

    private func toISBN13(fromISBN10 isbn10: String) -> String? {
        let upper = isbn10.uppercased()
        guard upper.count == 10 else { return nil }

        let prefix = "978" + String(upper.prefix(9))
        guard prefix.allSatisfy(\.isNumber) else { return nil }

        var sum = 0
        for (index, ch) in prefix.enumerated() {
            guard let digit = ch.wholeNumberValue else { return nil }
            sum += digit * (index % 2 == 0 ? 1 : 3)
        }
        let check = (10 - (sum % 10)) % 10
        return prefix + String(check)
    }

    private func toISBN10(fromISBN13 isbn13: String) -> String? {
        guard isbn13.count == 13, isbn13.hasPrefix("978") else { return nil }
        let core = String(isbn13.dropFirst(3).prefix(9))
        guard core.allSatisfy(\.isNumber) else { return nil }

        var sum = 0
        for (index, ch) in core.enumerated() {
            guard let digit = ch.wholeNumberValue else { return nil }
            sum += digit * (10 - index)
        }
        let remainder = 11 - (sum % 11)
        let check: String
        switch remainder {
        case 10:
            check = "X"
        case 11:
            check = "0"
        default:
            check = String(remainder)
        }

        return core + check
    }

    private func queryOpenLibrary(isbn: String) async throws -> BookLookupResult? {
        guard let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data") else {
            return nil
        }

        let data = try await fetchData(from: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = object.values.first as? [String: Any],
              let title = first["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let authors = first["authors"] as? [[String: Any]]
        let author = authors?.first?["name"] as? String ?? "Unknown Author"

        let subjects = first["subjects"] as? [[String: Any]]
        let category = subjects?.first?["name"] as? String ?? ""

        let cover = first["cover"] as? [String: Any]
        var coverURL = cover?["large"] as? String ?? cover?["medium"] as? String ?? cover?["small"] as? String ?? ""
        coverURL = coverURL.replacingOccurrences(of: "http://", with: "https://")

        return BookLookupResult(
            title: title,
            author: author,
            isbn: isbn,
            genre: mapGenre(from: category),
            coverURL: coverURL
        )
    }

    private func queryOpenLibrarySearch(query: String, preferredISBN: String? = nil) async throws -> BookLookupResult? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components?.url else { return nil }

        let data = try await fetchData(from: url)
        let response = try JSONDecoder().decode(OpenLibrarySearchResponse.self, from: data)
        guard let docs = response.docs, !docs.isEmpty else { return nil }

        let preferredNumeric = preferredISBN?.filter(\.isNumber)
        let doc: OpenLibrarySearchDoc?
        if let preferredNumeric {
            doc = docs.first { doc in
                doc.isbn?.contains(where: { $0.filter(\.isNumber) == preferredNumeric }) == true
            }
        } else {
            doc = docs.first
        }

        guard let doc,
              let rawTitle = doc.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTitle.isEmpty else {
            return nil
        }

        let author = doc.authorNames?.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAuthor = (author?.isEmpty == false) ? author! : "Unknown Author"
        let category = doc.subjects?.first ?? ""

        let resolvedISBN: String
        if let preferredNumeric, preferredNumeric.count == 10 || preferredNumeric.count == 13 {
            resolvedISBN = preferredNumeric
        } else if let firstValidISBN = doc.isbn?.first(where: { code in
            let numeric = code.filter(\.isNumber)
            return numeric.count == 10 || numeric.count == 13
        }) {
            resolvedISBN = firstValidISBN.filter(\.isNumber)
        } else {
            resolvedISBN = ""
        }

        var coverURL = ""
        if let coverID = doc.coverID {
            coverURL = "https://covers.openlibrary.org/b/id/\(coverID)-L.jpg"
        } else if !resolvedISBN.isEmpty {
            coverURL = "https://covers.openlibrary.org/b/isbn/\(resolvedISBN)-L.jpg?default=false"
        }

        return BookLookupResult(
            title: rawTitle,
            author: resolvedAuthor,
            isbn: resolvedISBN,
            genre: mapGenre(from: category),
            coverURL: coverURL
        )
    }

    private func queryWorldCat(isbn: String) async throws -> BookLookupResult? {
        var components = URLComponents(string: "https://classify.oclc.org/classify2/Classify")
        components?.queryItems = [
            URLQueryItem(name: "isbn", value: isbn),
            URLQueryItem(name: "summary", value: "true")
        ]
        guard let url = components?.url else { return nil }

        let data = try await fetchData(from: url)
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        guard let workTag = firstRegexMatch(pattern: "<work\\b[^>]*>", in: xml) else { return nil }

        let rawTitle = xmlAttribute(named: "title", in: workTag)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title = rawTitle, !title.isEmpty else { return nil }

        let author = xmlAttribute(named: "author", in: workTag)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAuthor = (author?.isEmpty == false) ? author! : "Unknown Author"

        return BookLookupResult(
            title: title,
            author: resolvedAuthor,
            isbn: isbn,
            genre: .other,
            coverURL: ""
        )
    }

    private func enrichAndValidateCover(_ result: BookLookupResult, isbnCandidates: [String]) async -> BookLookupResult {
        let currentCover = result.coverURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Google Books image URLs are reliable — trust without validation
        if !currentCover.isEmpty,
           currentCover.contains("googleapis.com") || currentCover.contains("books.google") {
            return result
        }

        // Collect all possible cover URL candidates for validation
        var candidates: [String] = []
        func appendUnique(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else { return }
            candidates.append(trimmed)
        }

        // Start with whatever the lookup returned
        appendUnique(currentCover)

        // Open Library ISBN-based cover URLs
        var seenISBNs = Set<String>()
        for raw in [result.isbn.filter(\.isNumber)] + isbnCandidates {
            let normalized = raw.filter { $0.isNumber || $0 == "X" || $0 == "x" }.uppercased()
            guard normalized.count == 10 || normalized.count == 13, !seenISBNs.contains(normalized) else { continue }
            seenISBNs.insert(normalized)
            appendUnique("https://covers.openlibrary.org/b/isbn/\(normalized)-L.jpg?default=false")
        }

        // Google metadata cover search — if found, trust it immediately
        if let googleCover = await bestEffort({ try await queryGoogleCover(query: "intitle:\(result.title) inauthor:\(result.author)") }) {
            return resultWithCover(result, coverURL: googleCover)
        }

        // Open Library metadata cover search
        if let metadataCover = await bestEffort({ try await queryOpenLibraryCoverByMetadata(title: result.title, author: result.author) }) {
            appendUnique(metadataCover)
        }

        // Validate all non-Google candidates — return first that actually serves an image
        if let validated = await bestEffort({ try await firstReachableCoverURL(from: candidates) }) {
            return resultWithCover(result, coverURL: validated)
        }

        return resultWithCover(result, coverURL: "")
    }

    private func resultWithCover(_ result: BookLookupResult, coverURL: String) -> BookLookupResult {
        BookLookupResult(
            title: result.title,
            author: result.author,
            isbn: result.isbn,
            genre: result.genre,
            coverURL: coverURL
        )
    }

    private func queryGoogleCover(query: String) async throws -> String? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=\(encoded)&maxResults=10") else {
            return nil
        }

        let data = try await fetchData(from: url)
        let response = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
        guard let items = response.items else { return nil }

        for item in items {
            let cover = normalizedGoogleImageURL(from: item.volumeInfo.imageLinks)
            if !cover.isEmpty {
                return cover
            }
        }

        return nil
    }

    private func queryOpenLibraryCoverByMetadata(title: String, author: String) async throws -> String? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "author", value: author),
            URLQueryItem(name: "limit", value: "10")
        ]

        guard let url = components?.url else { return nil }

        let data = try await fetchData(from: url)
        let response = try JSONDecoder().decode(OpenLibrarySearchResponse.self, from: data)
        guard let docs = response.docs else { return nil }

        if let coverID = docs.compactMap(\.coverID).first {
            return "https://covers.openlibrary.org/b/id/\(coverID)-L.jpg"
        }

        for isbn in docs.compactMap(\.isbn).flatMap({ $0 }) {
            let normalized = isbn.filter(\.isNumber)
            guard normalized.count == 10 || normalized.count == 13 else { continue }
            return "https://covers.openlibrary.org/b/isbn/\(normalized)-L.jpg?default=false"
        }

        return nil
    }

    private func firstReachableCoverURL(from candidates: [String]) async throws -> String? {
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 6
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                guard (200...299).contains(http.statusCode) else { continue }

                if let mimeType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
                   mimeType.contains("image") {
                    return candidate
                }

                // Some servers don't return Content-Type on HEAD — accept if path looks like an image
                let path = url.path.lowercased()
                if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") || path.hasSuffix(".png") || path.hasSuffix(".webp") {
                    return candidate
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private func bestEffort<T>(_ operation: () async throws -> T?) async -> T? {
        do {
            return try await operation()
        } catch {
            return nil
        }
    }

    private func fetchData(from url: URL, retries: Int = 2) async throws -> Data {
        var lastError: Error?

        for attempt in 0...retries {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return data
                }

                if (200...299).contains(http.statusCode) {
                    return data
                }

                let error = BookLookupNetworkError.httpStatus(http.statusCode)
                if shouldRetry(error: error), attempt < retries {
                    try await Task.sleep(nanoseconds: UInt64((attempt + 1) * 500_000_000))
                    continue
                }
                throw error
            } catch {
                lastError = error
                if shouldRetry(error: error), attempt < retries {
                    try await Task.sleep(nanoseconds: UInt64((attempt + 1) * 500_000_000))
                    continue
                }
                throw error
            }
        }

        throw lastError ?? BookLookupNetworkError.unknown
    }

    private func shouldRetry(error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        if let networkError = error as? BookLookupNetworkError {
            switch networkError {
            case .httpStatus(let statusCode):
                return statusCode == 429 || (500...599).contains(statusCode)
            case .unknown:
                return false
            }
        }

        return false
    }

    private func firstRegexMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matchRange])
    }

    private func xmlAttribute(named attribute: String, in tag: String) -> String? {
        let escapedAttribute = NSRegularExpression.escapedPattern(for: attribute)
        let pattern = "\(escapedAttribute)\\s*=\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: tag) else {
            return nil
        }
        return String(tag[valueRange])
    }

}

private struct GoogleBooksResponse: Decodable {
    let items: [GoogleBookItem]?
}

private struct GoogleBookItem: Decodable {
    let id: String?
    let volumeInfo: GoogleBookVolumeInfo
}

private struct GoogleBookVolumeInfo: Decodable {
    let title: String?
    let authors: [String]?
    let categories: [String]?
    let industryIdentifiers: [GoogleBookIdentifier]?
    let imageLinks: GoogleBookImageLinks?
}

private struct GoogleBookIdentifier: Decodable {
    let type: String?
    let identifier: String?
}

private struct GoogleBookImageLinks: Decodable {
    let smallThumbnail: String?
    let thumbnail: String?
    let small: String?
    let medium: String?
    let large: String?
    let extraLarge: String?
}

private struct OpenLibrarySearchResponse: Decodable {
    let docs: [OpenLibrarySearchDoc]?
}

private struct OpenLibrarySearchDoc: Decodable {
    let title: String?
    let authorNames: [String]?
    let subjects: [String]?
    let coverID: Int?
    let isbn: [String]?

    enum CodingKeys: String, CodingKey {
        case title
        case authorNames = "author_name"
        case subjects = "subject"
        case coverID = "cover_i"
        case isbn
    }
}

private enum BookLookupNetworkError: Error {
    case httpStatus(Int)
    case unknown
}
