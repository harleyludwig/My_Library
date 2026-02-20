import SwiftUI

struct BookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var libraryStore: LibraryStore
    @Binding var book: Book

    @AppStorage("defaultLendReminderDays") private var defaultReminderDays = 14

    @State private var showingLendSheet = false
    @State private var showingEditSheet = false
    @State private var lendToName = ""
    @State private var enableReminder = true
    @State private var reminderDays = 14
    @State private var pendingDeleteID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topHero
                detailsCard
                seriesCard
                tagsCard
                lendingCard
                notesCard
            }
            .padding()
        }
        .background(LibraryTheme.backgroundGradient.opacity(0.35).ignoresSafeArea())
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingLendSheet) {
            lendSheet
        }
        .sheet(isPresented: $showingEditSheet) {
            EditBookView(book: $book, onDelete: deleteBook)
        }
        .onDisappear {
            guard let pendingDeleteID else { return }
            libraryStore.removeBook(pendingDeleteID)
            self.pendingDeleteID = nil
        }
    }

    private var topHero: some View {
        HStack(spacing: 16) {
            CoverArtView(coverURL: book.coverURL, title: book.title, width: 120, height: 180)

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.title3.bold())
                    .foregroundStyle(LibraryTheme.textPrimary)
                Text(book.author)
                    .font(.headline)
                    .foregroundStyle(LibraryTheme.textSecondary)

                Text(book.genre.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.blue.opacity(0.16), in: Capsule())

                Text(book.format.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.18), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private var detailsCard: some View {
        InfoCard(title: "Details") {
            LabeledContent("Added", value: book.createdAt.formatted(date: .abbreviated, time: .omitted))
        }
    }

    private var seriesCard: some View {
        InfoCard(title: "Series") {
            if book.isPartOfSeries {
                LabeledContent("Series", value: book.seriesName.isEmpty ? "Unnamed series" : book.seriesName)
            } else {
                Text("Standalone title")
                    .foregroundStyle(LibraryTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var tagsCard: some View {
        if !book.tags.isEmpty {
            InfoCard(title: "Tags") {
                FlowTagsView(tags: book.tags)
            }
        }
    }

    private var lendingCard: some View {
        InfoCard(title: "Lending") {
            if book.isLent {
                LabeledContent("Lent To", value: book.lentTo)
                if let date = book.lentDate {
                    LabeledContent("Lent On", value: date.formatted(date: .abbreviated, time: .omitted))
                }
                if let reminderDate = book.reminderDate {
                    LabeledContent("Reminder", value: reminderDate.formatted(date: .abbreviated, time: .shortened))
                }

                Button("Mark as Returned") {
                    book.markReturned()
                    LendingReminderService.removeReminder(forBookID: book.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                Text("Currently in your library")
                    .foregroundStyle(LibraryTheme.textSecondary)

                Button("Lend This Book") {
                    lendToName = ""
                    reminderDays = defaultReminderDays
                    enableReminder = true
                    showingLendSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.70, green: 0.20, blue: 0.22))
                .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var notesCard: some View {
        if !book.notes.isEmpty {
            InfoCard(title: "Notes") {
                Text(book.notes)
                    .foregroundStyle(LibraryTheme.textPrimary)
            }
        }
    }

    private var lendSheet: some View {
        NavigationStack {
            Form {
                TextField("Who did you lend it to?", text: $lendToName)

                Toggle("Set reminder", isOn: $enableReminder)

                if enableReminder {
                    Stepper("Remind in \(reminderDays) days", value: $reminderDays, in: 1...120)
                }
            }
            .navigationTitle("Lend Book")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showingLendSheet = false
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let days = enableReminder ? reminderDays : nil
                        book.lend(to: lendToName, remindAfterDays: days)

                        Task {
                            await LendingReminderService.scheduleReminder(for: book)
                        }

                        showingLendSheet = false
                    }
                    .disabled(lendToName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(270)])
    }

    private func deleteBook() {
        let id = book.id
        LendingReminderService.removeReminder(forBookID: id)
        pendingDeleteID = id
        showingEditSheet = false
        dismiss()
    }
}

private struct InfoCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LibraryTheme.paper.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LibraryTheme.shelfBrown.opacity(0.18), lineWidth: 1)
        )
        .foregroundStyle(LibraryTheme.textPrimary)
    }
}

private struct FlowTagsView: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
