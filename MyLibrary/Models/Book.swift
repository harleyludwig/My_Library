import Foundation

enum BookGenre: String, CaseIterable, Codable, Identifiable {
    case fiction = "Fiction"
    case fantasy = "Fantasy"
    case mystery = "Mystery"
    case thriller = "Thriller"
    case scienceFiction = "Science Fiction"
    case romance = "Romance"
    case historical = "Historical"
    case biography = "Biography"
    case selfHelp = "Self Help"
    case children = "Children"
    case nonFiction = "Nonfiction"
    case other = "Other"

    var id: String { rawValue }
}

enum BookFormat: String, CaseIterable, Codable, Identifiable {
    case physical = "Physical"
    case digital = "Digital"

    var id: String { rawValue }
}

struct Book: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var author: String
    var barcode: String
    var isbn: String
    var genre: BookGenre
    var isPartOfSeries: Bool
    var seriesName: String
    var seriesNumber: Int?
    var format: BookFormat
    var coverURL: String
    var tags: [String]
    var notes: String
    var lentTo: String
    var lentDate: Date?
    var reminderDate: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        barcode: String = "",
        isbn: String = "",
        genre: BookGenre = .other,
        isPartOfSeries: Bool = false,
        seriesName: String = "",
        seriesNumber: Int? = nil,
        format: BookFormat = .physical,
        coverURL: String = "",
        tags: [String] = [],
        notes: String = "",
        lentTo: String = "",
        lentDate: Date? = nil,
        reminderDate: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.barcode = barcode
        self.isbn = isbn
        self.genre = genre
        self.isPartOfSeries = isPartOfSeries
        self.seriesName = seriesName
        self.seriesNumber = seriesNumber
        self.format = format
        self.coverURL = coverURL
        self.tags = tags
        self.notes = notes
        self.lentTo = lentTo
        self.lentDate = lentDate
        self.reminderDate = reminderDate
        self.createdAt = createdAt
    }

    var isLent: Bool {
        !lentTo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func lend(to person: String, remindAfterDays: Int?) {
        lentTo = person.trimmingCharacters(in: .whitespacesAndNewlines)
        lentDate = .now

        if let remindAfterDays, remindAfterDays > 0 {
            reminderDate = Calendar.current.date(byAdding: .day, value: remindAfterDays, to: .now)
        } else {
            reminderDate = nil
        }
    }

    mutating func markReturned() {
        lentTo = ""
        lentDate = nil
        reminderDate = nil
    }
}
