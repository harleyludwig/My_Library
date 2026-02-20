import Foundation

enum CSVBookImportSource: String {
    case kindle
    case audible
}

struct CSVBookImportService {
    func parseBooks(from data: Data, source: CSVBookImportSource) -> [Book] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            return []
        }

        let rows = parseCSVRows(text)
        guard rows.count > 1 else { return [] }

        let headers = rows[0].map { normalizeHeader($0) }
        let titleIndex = firstMatchingIndex(in: headers, keys: ["title", "name"])
        let authorIndex = firstMatchingIndex(in: headers, keys: ["author", "authors", "author(s)"])
        let isbnIndex = firstMatchingIndex(in: headers, keys: ["isbn", "isbn-13", "isbn13"])
        let asinIndex = firstMatchingIndex(in: headers, keys: ["asin"])

        guard let titleIndex else { return [] }

        var books: [Book] = []

        for row in rows.dropFirst() {
            guard titleIndex < row.count else { continue }

            let title = row[titleIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { continue }

            let author: String
            if let authorIndex, authorIndex < row.count {
                let value = row[authorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                author = value.isEmpty ? defaultAuthor(for: source) : value
            } else {
                author = defaultAuthor(for: source)
            }

            let isbn = valueIfPresent(row: row, index: isbnIndex)
            let asin = valueIfPresent(row: row, index: asinIndex)

            var notes = "Imported from \(source.rawValue.capitalized) CSV"
            if !asin.isEmpty {
                notes += " | ASIN: \(asin)"
            }

            let book = Book(
                title: title,
                author: author,
                isbn: isbn,
                genre: .other,
                format: .digital,
                notes: notes
            )

            books.append(book)
        }

        return books
    }

    private func defaultAuthor(for source: CSVBookImportSource) -> String {
        switch source {
        case .kindle:
            return "Unknown Kindle Author"
        case .audible:
            return "Unknown Audible Author"
        }
    }

    private func valueIfPresent(row: [String], index: Int?) -> String {
        guard let index, index < row.count else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstMatchingIndex(in headers: [String], keys: [String]) -> Int? {
        for key in keys {
            if let index = headers.firstIndex(where: { $0 == normalizeHeader(key) }) {
                return index
            }
        }
        return nil
    }

    private func normalizeHeader(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
    }

    private func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        for char in text {
            if char == "\"" {
                inQuotes.toggle()
                continue
            }

            if char == "," && !inQuotes {
                row.append(field)
                field = ""
                continue
            }

            if (char == "\n" || char == "\r") && !inQuotes {
                if !field.isEmpty || !row.isEmpty {
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                }
                continue
            }

            field.append(char)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
}
