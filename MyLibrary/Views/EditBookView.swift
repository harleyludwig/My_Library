import SwiftUI

struct EditBookView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var book: Book
    var onDelete: (() -> Void)?

    @State private var title = ""
    @State private var author = ""
    @State private var barcode = ""
    @State private var isbn = ""
    @State private var genre: BookGenre = .other
    @State private var format: BookFormat = .physical
    @State private var coverURL = ""
    @State private var notes = ""
    @State private var isPartOfSeries = false
    @State private var seriesName = ""
    @State private var seriesNumber = ""
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Book") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("ISBN", text: $isbn)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Barcode", text: $barcode)
                        .keyboardType(.numbersAndPunctuation)

                    Picker("Genre", selection: $genre) {
                        ForEach(BookGenre.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }

                    Picker("Format", selection: $format) {
                        ForEach(BookFormat.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }

                    TextField("Cover URL", text: $coverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }

                Section("Series") {
                    Toggle("Part of a series", isOn: $isPartOfSeries)
                    if isPartOfSeries {
                        TextField("Series name", text: $seriesName)
                        TextField("Series number", text: $seriesNumber)
                            .keyboardType(.numberPad)
                    }
                }

                Section("Tags") {
                    HStack {
                        TextField("Add tag", text: $newTag)
                        Button("Add") {
                            addTag()
                        }
                        .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if tags.isEmpty {
                        Text("No tags")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tags, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Spacer()
                                Button(role: .destructive) {
                                    tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...7)
                }

                if onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Book", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Edit Book")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: loadFromBook)
            .alert("Delete this book?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func loadFromBook() {
        title = book.title
        author = book.author
        barcode = book.barcode
        isbn = book.isbn
        genre = book.genre
        format = book.format
        coverURL = book.coverURL
        notes = book.notes
        isPartOfSeries = book.isPartOfSeries
        seriesName = book.seriesName
        seriesNumber = book.seriesNumber.map(String.init) ?? ""
        tags = book.tags
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newTag = ""
            return
        }

        tags.append(trimmed)
        tags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        newTag = ""
    }

    private func save() {
        book.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        book.author = author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Author" : author
        book.barcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        book.isbn = isbn.trimmingCharacters(in: .whitespacesAndNewlines)
        book.genre = genre
        book.format = format
        book.coverURL = coverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        book.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        book.isPartOfSeries = isPartOfSeries
        book.seriesName = seriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        book.seriesNumber = Int(seriesNumber)
        book.tags = tags

        dismiss()
    }
}
