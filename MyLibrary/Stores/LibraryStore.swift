import Foundation

final class LibraryStore: ObservableObject {
    @Published var books: [Book] = [] {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    private let saveURL: URL
    private var isLoading = false

    init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        saveURL = documentsDirectory.appendingPathComponent("library_books.json")
        load()
    }

    func addBook(_ book: Book) {
        books.append(book)
        sortBooks()
    }

    func addBooks(_ incomingBooks: [Book]) -> Int {
        guard !incomingBooks.isEmpty else { return 0 }

        var added = 0
        var seenKeys = Set(books.map(makeDedupKey))

        for book in incomingBooks {
            let key = makeDedupKey(book)
            if seenKeys.contains(key) { continue }
            books.append(book)
            seenKeys.insert(key)
            added += 1
        }

        if added > 0 {
            sortBooks()
        }

        return added
    }

    func updateBook(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index] = book
        sortBooks()
    }

    func removeBook(_ id: UUID) {
        books.removeAll { $0.id == id }
    }

    func backupData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(books)
    }

    func restoreBackupData(_ data: Data) throws {
        let decoded = try JSONDecoder().decode([Book].self, from: data)
        books = decoded
        sortBooks()
    }

    private func makeDedupKey(_ book: Book) -> String {
        let title = book.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let author = book.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isbn = book.isbn.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(title)|\(author)|\(isbn)"
    }

    private func sortBooks() {
        books.sort {
            if $0.title == $1.title {
                return $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        guard let data = try? Data(contentsOf: saveURL) else {
            books = []
            return
        }

        do {
            books = try JSONDecoder().decode([Book].self, from: data)
            sortBooks()
        } catch {
            books = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(books)
            try data.write(to: saveURL, options: [.atomic])
        } catch {
            // Keep silent in-app; persistence failure should not block interaction.
        }
    }
}
