import SwiftUI

struct LentBooksView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    private var lentBooks: [Book] {
        libraryStore.books
            .filter { $0.isLent }
            .sorted { ($0.lentDate ?? .distantPast) > ($1.lentDate ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LibraryTheme.backgroundGradient
                    .ignoresSafeArea()

                if lentBooks.isEmpty {
                    ContentUnavailableView {
                        Label("No Lent Books", systemImage: "checkmark.seal")
                    } description: {
                        Text("Books you lend out will appear here.")
                    }
                } else {
                    List {
                        ForEach(lentBooks) { book in
                            if let index = libraryStore.books.firstIndex(where: { $0.id == book.id }) {
                                NavigationLink {
                                    BookDetailView(book: $libraryStore.books[index])
                                } label: {
                                    HStack(spacing: 12) {
                                        CoverArtView(coverURL: book.coverURL, title: book.title, width: 50, height: 72)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(book.title)
                                                .font(.headline)
                                            Text("Lent to \(book.lentTo)")
                                                .foregroundStyle(LibraryTheme.textSecondary)
                                            if let lentDate = book.lentDate {
                                                Text(lentDate.formatted(date: .abbreviated, time: .omitted))
                                                    .font(.caption)
                                                    .foregroundStyle(LibraryTheme.textSecondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(LibraryTheme.paper.opacity(0.92))
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Lending")
        }
    }
}
