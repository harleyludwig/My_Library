import SwiftUI
import AVFoundation
import VisionKit

struct AddBookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var libraryStore: LibraryStore

    @State private var barcode = ""
    @State private var title = ""
    @State private var author = ""
    @State private var isbn = ""
    @State private var genre: BookGenre = .other
    @State private var format: BookFormat = .physical
    @State private var coverURL = ""
    @State private var isPartOfSeries = false
    @State private var seriesName = ""
    @State private var seriesNumber = ""
    @State private var notes = ""

    @State private var showingScanner = false
    @State private var showingTextScanner = false
    @State private var lookupInProgress = false
    @State private var lookupErrorMessage: String?
    @State private var showingCameraDeniedAlert = false
    @State private var autoOpenedScanner = false
    @State private var showingDuplicateAlert = false
    @State private var pendingDuplicateBook: Book?
    @State private var duplicateMessage = ""
    @State private var coverLookupInProgress = false
    @State private var coverLookupMessage: String?
    @State private var titleSearchQuery = ""
    @State private var titleSearchInProgress = false
    @State private var showTitleSearch = false

    private let lookupService = BookLookupService()

    var body: some View {
        NavigationStack {
            Form {
                scanAndLookupSection
                basicDetailsSection
                seriesSection
                notesSection
            }
            .scrollContentBackground(.hidden)
            .background(LibraryTheme.backgroundGradient.opacity(0.3))
            .navigationTitle("Add Book")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveBook()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showingScanner) {
                scannerOverlay
            }
            .sheet(isPresented: $showingTextScanner) {
                textScannerOverlay
            }
            .alert("Camera Access Required", isPresented: $showingCameraDeniedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enable camera access in Settings to scan barcodes.")
            }
            .alert("Possible Duplicate", isPresented: $showingDuplicateAlert) {
                Button("Add Anyway") {
                    if let pendingDuplicateBook {
                        libraryStore.addBook(pendingDuplicateBook)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDuplicateBook = nil
                }
            } message: {
                Text(duplicateMessage)
            }
            .onAppear {
                guard !autoOpenedScanner else { return }
                autoOpenedScanner = true
                handleScanTapped()
            }
        }
    }

    private var scannerOverlay: some View {
        ZStack(alignment: .bottom) {
            BarcodeScannerView { code in
                barcode = code
                showingScanner = false
                Task {
                    await lookupBook(for: code, autoSaveAndDismissOnSuccess: true)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Scan a barcode to add quickly")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)

                if #available(iOS 16.0, *), TextScannerView.isSupported {
                    Button {
                        showingScanner = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showingTextScanner = true
                        }
                    } label: {
                        Label("Scan Title Text Instead", systemImage: "text.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(LibraryTheme.accent)
                    }
                }

                Button("Enter Book Manually") {
                    showingScanner = false
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.black)
            }
            .padding()
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showingScanner = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 5)
                    .padding(.top, 10)
                    .padding(.trailing, 10)
            }
        }
    }

    private var scanAndLookupSection: some View {
        Section("Barcode") {
            TextField("Barcode / ISBN", text: $barcode)
                .textInputAutocapitalization(.never)
                .keyboardType(.numbersAndPunctuation)

            HStack {
                Button {
                    handleScanTapped()
                } label: {
                    Label("Scan Barcode", systemImage: "barcode.viewfinder")
                }

                if #available(iOS 16.0, *), TextScannerView.isSupported {
                    Button {
                        handleTextScanTapped()
                    } label: {
                        Label("Scan Text", systemImage: "text.viewfinder")
                    }
                }

                Spacer()

                Button {
                    Task {
                        await lookupBook(for: barcode, autoSaveAndDismissOnSuccess: false)
                    }
                } label: {
                    if lookupInProgress {
                        ProgressView()
                    } else {
                        Text("Look Up")
                    }
                }
                .disabled(barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lookupInProgress)
            }

            if let lookupErrorMessage {
                Text(lookupErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if showTitleSearch {
                titleSearchSection
            }
        }
    }

    private var titleSearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Search by title instead:")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(LibraryTheme.textSecondary)

            HStack {
                TextField("Book title", text: $titleSearchQuery)
                    .textInputAutocapitalization(.words)
                    .onSubmit {
                        Task { await searchByTitle() }
                    }

                Button {
                    Task { await searchByTitle() }
                } label: {
                    if titleSearchInProgress {
                        ProgressView()
                    } else {
                        Text("Search")
                    }
                }
                .disabled(titleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || titleSearchInProgress)
            }
        }
    }

    private var textScannerOverlay: some View {
        ZStack(alignment: .bottom) {
            if #available(iOS 16.0, *) {
                TextScannerView { text in
                    showingTextScanner = false
                    titleSearchQuery = text
                    showTitleSearch = true
                    Task {
                        await searchByTitle()
                    }
                }
                .ignoresSafeArea()
            }

            VStack(spacing: 12) {
                Text("Tap on the book title to scan it")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)

                Button("Cancel") {
                    showingTextScanner = false
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.black)
            }
            .padding()
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showingTextScanner = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 5)
                    .padding(.top, 10)
                    .padding(.trailing, 10)
            }
        }
    }

    private var basicDetailsSection: some View {
        Section("Book Details") {
            TextField("Title", text: $title)
            TextField("Author", text: $author)
            TextField("ISBN", text: $isbn)
                .textInputAutocapitalization(.never)
                .keyboardType(.numbersAndPunctuation)
            TextField("Cover Image URL", text: $coverURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)

            HStack {
                Button {
                    Task {
                        await lookupCoverFromDetails()
                    }
                } label: {
                    if coverLookupInProgress {
                        ProgressView()
                    } else {
                        Label("Find Cover from Details", systemImage: "photo")
                    }
                }
                .disabled(
                    coverLookupInProgress
                        || (
                            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && isbn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                )

                Spacer()
            }

            if let coverLookupMessage {
                Text(coverLookupMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Genre", selection: $genre) {
                ForEach(BookGenre.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }

            Picker("Format", selection: $format) {
                ForEach(BookFormat.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }

            if !coverURL.isEmpty {
                HStack {
                    Spacer()
                    CoverArtView(coverURL: coverURL, title: title.isEmpty ? "Book" : title, width: 110, height: 160)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private var seriesSection: some View {
        Section("Series") {
            Toggle("Part of a series", isOn: $isPartOfSeries)

            if isPartOfSeries {
                TextField("Series name", text: $seriesName)
                TextField("Series number", text: $seriesNumber)
                    .keyboardType(.numberPad)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private func handleScanTapped() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    showingScanner = granted
                    showingCameraDeniedAlert = !granted
                }
            }
        default:
            showingCameraDeniedAlert = true
        }
    }

    private func handleTextScanTapped() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingTextScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    showingTextScanner = granted
                    showingCameraDeniedAlert = !granted
                }
            }
        default:
            showingCameraDeniedAlert = true
        }
    }

    private func lookupBook(for rawCode: String, autoSaveAndDismissOnSuccess: Bool) async {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        lookupErrorMessage = nil
        lookupInProgress = true

        do {
            guard let result = try await lookupService.lookup(barcode: code) else {
                lookupErrorMessage = "No book found for that barcode."
                showTitleSearch = true
                lookupInProgress = false
                return
            }

            if title.isEmpty { title = result.title }
            if author.isEmpty { author = result.author }
            if isbn.isEmpty { isbn = result.isbn }
            if coverURL.isEmpty { coverURL = result.coverURL }
            genre = result.genre
            lookupInProgress = false

            if autoSaveAndDismissOnSuccess {
                saveBook()
            }
        } catch {
            lookupErrorMessage = "Lookup failed."
            showTitleSearch = true
            lookupInProgress = false
        }
    }

    private func searchByTitle() async {
        let query = titleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        titleSearchInProgress = true
        lookupErrorMessage = nil

        do {
            guard let result = try await lookupService.lookupByTitle(query: query) else {
                lookupErrorMessage = "No book found for \"\(query)\". Try a different title or enter details manually."
                titleSearchInProgress = false
                return
            }

            if title.isEmpty { title = result.title }
            if author.isEmpty { author = result.author }
            if isbn.isEmpty { isbn = result.isbn }
            if coverURL.isEmpty { coverURL = result.coverURL }
            genre = result.genre
            showTitleSearch = false
            lookupErrorMessage = nil
            titleSearchInProgress = false
        } catch {
            lookupErrorMessage = "Title search failed. You can enter details manually."
            titleSearchInProgress = false
        }
    }

    private func lookupCoverFromDetails() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedISBN = isbn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedAuthor.isEmpty || !trimmedISBN.isEmpty else {
            coverLookupMessage = "Enter title, author, or ISBN first."
            return
        }

        coverLookupInProgress = true
        coverLookupMessage = nil

        do {
            if let foundCover = try await lookupService.lookupCover(title: trimmedTitle, author: trimmedAuthor, isbn: trimmedISBN) {
                coverURL = foundCover
            } else {
                coverLookupMessage = "No cover found from those details. You can paste a URL manually."
            }
        } catch {
            coverLookupMessage = "Cover lookup failed. You can paste a URL manually."
        }

        coverLookupInProgress = false
    }

    private func saveBook() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let book = Book(
            title: trimmedTitle,
            author: author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Author" : author,
            barcode: barcode.trimmingCharacters(in: .whitespacesAndNewlines),
            isbn: isbn.trimmingCharacters(in: .whitespacesAndNewlines),
            genre: genre,
            isPartOfSeries: isPartOfSeries,
            seriesName: seriesName.trimmingCharacters(in: .whitespacesAndNewlines),
            seriesNumber: Int(seriesNumber),
            format: format,
            coverURL: coverURL.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if let duplicate = findDuplicate(for: book) {
            pendingDuplicateBook = book
            duplicateMessage = "\"\(duplicate.title)\" by \(duplicate.author) is already in your library. Add this book anyway?"
            showingDuplicateAlert = true
            return
        }

        libraryStore.addBook(book)
        dismiss()
    }

    private func findDuplicate(for candidate: Book) -> Book? {
        let candidateISBN = normalizedID(candidate.isbn)
        if !candidateISBN.isEmpty {
            if let match = libraryStore.books.first(where: { normalizedID($0.isbn) == candidateISBN }) {
                return match
            }
        }

        let candidateBarcode = normalizedID(candidate.barcode)
        if !candidateBarcode.isEmpty {
            if let match = libraryStore.books.first(where: { normalizedID($0.barcode) == candidateBarcode }) {
                return match
            }
        }

        let candidateTitle = normalizedText(candidate.title)
        let candidateAuthor = normalizedText(candidate.author)
        guard !candidateTitle.isEmpty, !candidateAuthor.isEmpty else { return nil }

        return libraryStore.books.first { existing in
            normalizedText(existing.title) == candidateTitle
                && normalizedText(existing.author) == candidateAuthor
        }
    }

    private func normalizedID(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    private func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
