import SwiftUI

enum LibraryDisplayMode: String, CaseIterable, Identifiable {
    case shelf = "Shelf"
    case list = "List"
    case author = "Author"

    var id: String { rawValue }
}

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case title = "Title"
    case author = "Author"
    case dateAdded = "Date Added"

    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    @AppStorage("libraryDisplayMode") private var displayModeRaw = LibraryDisplayMode.shelf.rawValue
    @AppStorage("librarySortOrder") private var sortOrderRaw = LibrarySortOrder.title.rawValue

    @State private var searchText = ""
    @State private var showingAddBook = false
    @State private var genreFilter: BookGenre?
    @State private var authorFilter: String?
    @State private var formatFilter: BookFormat?
    @State private var lentFilter: Bool?

    private var selectedDisplayMode: LibraryDisplayMode {
        LibraryDisplayMode(rawValue: displayModeRaw) ?? .shelf
    }

    private var selectedSortOrder: LibrarySortOrder {
        LibrarySortOrder(rawValue: sortOrderRaw) ?? .title
    }

    // O(1) index lookup instead of O(n) per cell
    private var bookIndexMap: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: libraryStore.books.enumerated().map { ($1.id, $0) })
    }

    private var filteredAndSortedBooks: [Book] {
        var books = libraryStore.books

        // Text search
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchText.lowercased()
            books = books.filter { book in
                book.title.lowercased().contains(query)
                    || book.author.lowercased().contains(query)
                    || book.genre.rawValue.lowercased().contains(query)
                    || book.isbn.lowercased().contains(query)
                    || book.barcode.lowercased().contains(query)
                    || book.tags.contains { $0.lowercased().contains(query) }
            }
        }

        // Filters
        if let genreFilter { books = books.filter { $0.genre == genreFilter } }
        if let authorFilter { books = books.filter { $0.author == authorFilter } }
        if let formatFilter { books = books.filter { $0.format == formatFilter } }
        if let lentFilter { books = books.filter { $0.isLent == lentFilter } }

        // Sort
        switch selectedSortOrder {
        case .title:
            books.sort {
                let cmp = $0.title.localizedCaseInsensitiveCompare($1.title)
                return cmp == .orderedSame
                    ? $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending
                    : cmp == .orderedAscending
            }
        case .author:
            books.sort {
                let cmp = $0.author.localizedCaseInsensitiveCompare($1.author)
                return cmp == .orderedSame
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : cmp == .orderedAscending
            }
        case .dateAdded:
            books.sort { $0.createdAt > $1.createdAt }
        }

        return books
    }

    private var alphabeticalSections: [(letter: String, books: [Book])] {
        let key: (Book) -> String = selectedSortOrder == .author
            ? { String($0.author.prefix(1)).uppercased() }
            : { String($0.title.prefix(1)).uppercased() }

        let grouped = Dictionary(grouping: filteredAndSortedBooks, by: key)
        return grouped
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    private var authorSections: [(author: String, books: [Book])] {
        let grouped = Dictionary(grouping: filteredAndSortedBooks) { $0.author }
        return grouped
            .map { ($0.key, $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
            .sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
    }

    private var allAuthors: [String] {
        Array(Set(libraryStore.books.map(\.author)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var hasActiveFilters: Bool {
        genreFilter != nil || authorFilter != nil || formatFilter != nil || lentFilter != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LibraryTheme.backgroundGradient
                    .ignoresSafeArea()

                if libraryStore.books.isEmpty {
                    ContentUnavailableView {
                        Label("No Books Yet", systemImage: "books.vertical")
                    } description: {
                        Text("Tap + to add your first book by barcode scan or manual entry.")
                    }
                } else if filteredAndSortedBooks.isEmpty {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try a different search or adjust your filters.")
                    }
                } else {
                    VStack(spacing: 0) {
                        headerControls
                        filterChips
                        libraryContent
                    }
                }
            }
            .navigationTitle("My Library")
            .searchable(text: $searchText, prompt: "Search title, author, genre, ISBN, tags")
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

    // MARK: - Header

    private var headerControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(filteredAndSortedBooks.count) books")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LibraryTheme.textPrimary)
                Spacer()

                Menu {
                    ForEach(LibrarySortOrder.allCases) { order in
                        Button {
                            sortOrderRaw = order.rawValue
                        } label: {
                            if order == selectedSortOrder {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                } label: {
                    Label("Sort: \(selectedSortOrder.rawValue)", systemImage: "arrow.up.arrow.down")
                        .font(.subheadline)
                        .foregroundStyle(LibraryTheme.accent)
                }
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
        .padding(.bottom, 4)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Genre chip
                Menu {
                    Button("All Genres") { genreFilter = nil }
                    Divider()
                    ForEach(BookGenre.allCases) { genre in
                        Button(genre.rawValue) { genreFilter = genre }
                    }
                } label: {
                    FilterChip(
                        label: genreFilter?.rawValue ?? "Genre",
                        isActive: genreFilter != nil,
                        systemImage: "tag"
                    )
                }

                // Author chip
                Menu {
                    Button("All Authors") { authorFilter = nil }
                    Divider()
                    ForEach(allAuthors, id: \.self) { author in
                        Button(author) { authorFilter = author }
                    }
                } label: {
                    FilterChip(
                        label: authorFilter ?? "Author",
                        isActive: authorFilter != nil,
                        systemImage: "person"
                    )
                }

                // Format chip
                Menu {
                    Button("All Formats") { formatFilter = nil }
                    Divider()
                    ForEach(BookFormat.allCases) { format in
                        Button(format.rawValue) { formatFilter = format }
                    }
                } label: {
                    FilterChip(
                        label: formatFilter?.rawValue ?? "Format",
                        isActive: formatFilter != nil,
                        systemImage: "book"
                    )
                }

                // Lent status chip
                Menu {
                    Button("All") { lentFilter = nil }
                    Divider()
                    Button("Lent Out") { lentFilter = true }
                    Button("Available") { lentFilter = false }
                } label: {
                    FilterChip(
                        label: lentFilter == true ? "Lent Out" : lentFilter == false ? "Available" : "Status",
                        isActive: lentFilter != nil,
                        systemImage: "person.line.dotted.person"
                    )
                }

                // Clear all button
                if hasActiveFilters {
                    Button {
                        genreFilter = nil
                        authorFilter = nil
                        formatFilter = nil
                        lentFilter = nil
                    } label: {
                        Text("Clear")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.red.opacity(0.1), in: Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Library Content

    @ViewBuilder
    private var libraryContent: some View {
        switch selectedDisplayMode {
        case .shelf:
            shelfView
        case .list:
            sectionedListView(
                sections: alphabeticalSections.map { (header: $0.letter, books: $0.books) }
            )
        case .author:
            sectionedListView(
                sections: authorSections.map { (header: $0.author, books: $0.books) }
            )
        }
    }

    // MARK: - Shelf View

    private var shelfView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 14) {
                ForEach(filteredAndSortedBooks) { book in
                    if let index = bookIndexMap[book.id] {
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
    }

    // MARK: - Sectioned List with Section Index

    private func sectionedListView(
        sections: [(header: String, books: [Book])]
    ) -> some View {
        let letters = sections.map { String($0.header.prefix(1)).uppercased() }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

        return ZStack(alignment: .trailing) {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        Section(section.header) {
                            ForEach(section.books) { book in
                                if let index = bookIndexMap[book.id] {
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
                        .id(section.header)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .trailing) {
                    SectionIndexBar(letters: letters) { letter in
                        if let target = sections.first(where: { String($0.header.prefix(1)).uppercased() == letter }) {
                            withAnimation {
                                proxy.scrollTo(target.header, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Section Index Bar

private struct SectionIndexBar: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @GestureState private var isDragging = false

    var body: some View {
        VStack(spacing: 1) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(LibraryTheme.accent)
                    .frame(width: 16, height: 14)
                    .onTapGesture { onSelect(letter) }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.trailing, 2)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isActive: Bool
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? LibraryTheme.accent.opacity(0.15) : LibraryTheme.shelfBrown.opacity(0.08), in: Capsule())
        .foregroundStyle(isActive ? LibraryTheme.accent : LibraryTheme.textSecondary)
        .overlay(
            Capsule().stroke(isActive ? LibraryTheme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Shelf Book Tile

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

// MARK: - Book Card View

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
