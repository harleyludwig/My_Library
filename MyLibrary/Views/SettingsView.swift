import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    @AppStorage("defaultLendReminderDays") private var defaultReminderDays = 14

    @State private var backupDocument = LibraryBackupDocument()
    @State private var showingBackupExporter = false
    @State private var showingBackupImporter = false
    @State private var showingKindleImporter = false
    @State private var showingAudibleImporter = false

    @State private var message = ""
    @State private var showingMessage = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    private let csvImporter = CSVBookImportService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Lending Reminders") {
                    Stepper("Default reminder: \(defaultReminderDays) days", value: $defaultReminderDays, in: 1...120)

                    HStack {
                        Text("Notifications")
                        Spacer()
                        Text(notificationLabel)
                            .foregroundStyle(.secondary)
                    }

                    Button("Enable Notifications") {
                        Task {
                            _ = await LendingReminderService.requestAuthorization()
                            await refreshNotificationStatus()
                        }
                    }
                }

                Section("Import Digital Libraries") {
                    Text("Direct Kindle/Audible account sync is limited, so this app imports exported CSV files.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Import Kindle CSV") {
                        showingKindleImporter = true
                    }

                    Button("Import Audible CSV") {
                        showingAudibleImporter = true
                    }
                }

                Section {
                    DisclosureGroup("Advanced Library Tools") {
                        Button("Create Backup File") {
                            createBackup()
                        }

                        Button("Restore From Backup") {
                            showingBackupImporter = true
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryTheme.backgroundGradient.opacity(0.35))
            .navigationTitle("Settings")
            .fileExporter(
                isPresented: $showingBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "my-library-backup"
            ) { result in
                switch result {
                case .success:
                    showMessage("Backup exported.")
                case .failure:
                    showMessage("Backup export failed.")
                }
            }
            .fileImporter(
                isPresented: $showingBackupImporter,
                allowedContentTypes: [.json]
            ) { result in
                handleBackupImport(result)
            }
            .fileImporter(
                isPresented: $showingKindleImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                handleCSVImport(result, source: .kindle)
            }
            .fileImporter(
                isPresented: $showingAudibleImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                handleCSVImport(result, source: .audible)
            }
            .alert("Settings", isPresented: $showingMessage) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message)
            }
            .task {
                await refreshNotificationStatus()
            }
        }
    }

    private var notificationLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "On"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await LendingReminderService.authorizationStatus()
    }

    private func createBackup() {
        do {
            backupDocument = try LibraryBackupDocument(data: libraryStore.backupData())
            showingBackupExporter = true
        } catch {
            showMessage("Could not create backup file.")
        }
    }

    private func handleBackupImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure:
            showMessage("Backup import canceled.")
        case .success(let url):
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let data = try Data(contentsOf: url)
                try libraryStore.restoreBackupData(data)
                showMessage("Backup restored.")
            } catch {
                showMessage("Backup restore failed.")
            }
        }
    }

    private func handleCSVImport(_ result: Result<URL, Error>, source: CSVBookImportSource) {
        switch result {
        case .failure:
            showMessage("CSV import canceled.")
        case .success(let url):
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let data = try Data(contentsOf: url)
                let imported = csvImporter.parseBooks(from: data, source: source)
                let added = libraryStore.addBooks(imported)
                showMessage("Imported \(added) books from \(source.rawValue.capitalized).")
            } catch {
                showMessage("CSV import failed.")
            }
        }
    }

    private func showMessage(_ text: String) {
        message = text
        showingMessage = true
    }
}
