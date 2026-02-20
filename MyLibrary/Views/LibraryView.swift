import SwiftUI

enum LibraryDisplayMode: String, CaseIterable, Identifiable {
    case shelf = "Shelf"
    case list = "List"

    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    @AppStorage("libraryDisplayMode") private var displayModeRaw = LibraryDisplayMode.shelf.rawValue

    @State private var searchText = ""
    @State private var showingAddBook = false
    
    private var selectedDisplayMode: LibraryDisplayMode {
        LibraryDisplayMode(rawValue: displayModeRaw) ?? .shelf
    }

    private var filteredBooks: [Book] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return libraryStore.books
        }

        let query = searchText.lowercased()
        return libraryStore.books.filter { book in
            book.title.lowercased().contains(query)
                || book.author.lowercased().contains(query)
                || book.genre.rawValue.lowercased().contains(query)
                || book.isbn.lowercased().contains(query)
                || book.barcode.lowercased().contains(query)
        }
    }

    private var groupedBooks: [(letter: String, books: [Book])] {
        let grouped = Dictionary(grouping: filteredBooks) { book in
            String(book.title.prefix(1)).uppercased()
        }

        return grouped
            .map { key, value in
                let sorted = value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                return (key, sorted)
            }
            .sorted { $0.letter < $1.letter }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LibraryTheme.backgroundGradient
                    .ignoresSafeArea()

                if filteredBooks.isEmpty {
                    ContentUnavailableView {
                        Label("No Books Yet", systemImage: "books.vertical")
                    } description: {
                        Text("Tap + to add your first book by barcode scan or manual entry.")
                    }
                } else {
                    VStack(spacing: 0) {
                        headerControls
                        libraryContent
                    }
                }
            }
            .navigationTitle("My Library")
            .searchable(text: $searchText, prompt: "Search title, author, genre, ISBN")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddBook = true
                    } label: {
                        Label("Add Book", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddBook) {
                AddBookView()
                    .environmentObject(libraryStore)
            }
        }
    }

    private var headerControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(filteredBooks.count) books")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LibraryTheme.textPrimary)
                Spacer()
            }

            Picker("Display", selection: Binding(
                get: { selectedDisplayMode },
                set: { displayModeRaw = $0.rawValue }
            )) {
                ForEach(LibraryDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var libraryContent: some View {
        switch selectedDisplayMode {
        case .shelf:
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 14) {
                    ForEach(filteredBooks) { book in
                        if let index = libraryStore.books.firstIndex(where: { $0.id == book.id }) {
                            NavigationLink {
                                BookDetailView(book: $libraryStore.books[index])
                            } label: {
                                ShelfBookTile(book: book)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
        case .list:
            List {
                ForEach(groupedBooks, id: \.letter) { section in
                    Section(section.letter) {
                        ForEach(section.books) { book in
                            if let index = libraryStore.books.firstIndex(where: { $0.id == book.id }) {
                                NavigationLink {
                                    BookDetailView(book: $libraryStore.books[index])
                                } label: {
                                    BookCardView(book: book)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct ShelfBookTile: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverArtView(coverURL: book.coverURL, title: book.title, width: 120, height: 170)

            Text(book.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(LibraryTheme.textPrimary)

            Text(book.author)
                .font(.caption)
                .foregroundStyle(LibraryTheme.textSecondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                if book.isLent {
                    Text("Lent")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }

                Text(book.format.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LibraryTheme.paper.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(LibraryTheme.shelfBrown.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct BookCardView: View {
    let book: Book

    var body: some View {
        HStack(spacing: 14) {
            CoverArtView(coverURL: book.coverURL, title: book.title)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(LibraryTheme.textPrimary)
                    .lineLimit(2)

                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(LibraryTheme.textSecondary)

                HStack(spacing: 8) {
                    genreTag
                    formatTag

                    if book.isLent {
                        Text("Lent")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LibraryTheme.paper.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(LibraryTheme.shelfBrown.opacity(0.2), lineWidth: 1)
        )
    }

    private var genreTag: some View {
        Text(book.genre.rawValue)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }

    private var formatTag: some View {
        Text(book.format.rawValue)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.green.opacity(0.15), in: Capsule())
            .foregroundStyle(.green)
    }
}
