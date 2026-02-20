# PROJECT_STRUCTURE.md

> Architectural map for AI agents and developers. Enables quick navigation and dependency analysis.

## Overview

**My Library** is a **native iOS application** built with **SwiftUI + Swift 5.0**.

### Stack

| Layer       | Technology                                                   |
| ----------- | ------------------------------------------------------------ |
| UI          | SwiftUI (iOS 17.0+, iPhone only, portrait)                   |
| Language    | Swift 5.0                                                    |
| Build       | XcodeGen 2.38.0+, Xcode                                     |
| Persistence | Local JSON file (app documents directory)                    |
| Networking  | URLSession with async/await                                  |
| Camera      | AVFoundation (barcode scanning)                              |
| Styles      | Custom theme (LibraryTheme), system fonts, forced light mode |
| Testing     | SwiftUI Previews (no formal test framework)                  |

---

## Project Tree

<details>
<summary>Expand full structure</summary>

```
.
├── README.md                        # Project documentation
├── PROJECT_STRUCTURE.md             # This file
├── project.yml                      # XcodeGen configuration
├── .gitignore                       # Git ignore rules
├── MyLibrary.xcodeproj/             # Generated Xcode project
│   ├── project.pbxproj
│   └── project.xcworkspace/
└── MyLibrary/                       # Source code
    ├── MyLibraryApp.swift           # @main entry point
    ├── Assets.xcassets/             # Image and color assets
    │   ├── AppIcon.appiconset/
    │   └── AccentColor.colorset/
    ├── Views/                       # SwiftUI views (8 files)
    │   ├── LibraryView.swift        # Main library grid/list display
    │   ├── AddBookView.swift        # Book addition + barcode scanning
    │   ├── EditBookView.swift       # Book metadata editing
    │   ├── BookDetailView.swift     # Book detail + lending UI
    │   ├── LentBooksView.swift      # Lending tracking view
    │   ├── SettingsView.swift       # Settings, import/export
    │   ├── BarcodeScannerView.swift # Camera barcode scanner
    │   └── CoverArtView.swift       # Book cover display component
    ├── Models/                      # Data models (2 files)
    │   ├── Book.swift               # Core Book model, BookGenre, BookFormat
    │   └── LibraryBackupDocument.swift # FileDocument for backup/restore
    ├── Stores/                      # State management (1 file)
    │   └── LibraryStore.swift       # ObservableObject — single source of truth
    ├── Services/                    # Business logic (3 files)
    │   ├── BookLookupService.swift  # Multi-API book metadata lookup
    │   ├── CSVBookImportService.swift # Kindle/Audible CSV import
    │   └── LendingReminderService.swift # UserNotifications scheduling
    ├── Theme/                       # Design system (1 file)
    │   └── LibraryTheme.swift       # Colors, gradients, design tokens
    └── Preview Content/             # SwiftUI preview assets
```

**Statistics:**

- Directories: ~78
- Swift source files: 16
- Total lines of Swift: ~2,560
- Views: 8
- Services: 3

</details>

---

## Build & Run

| Action                | Command / Method                                |
| --------------------- | ----------------------------------------------- |
| Generate Xcode project | `xcodegen generate` (requires project.yml)     |
| Build & run           | Open `MyLibrary.xcodeproj` in Xcode, ⌘R        |
| Run on device         | Xcode → select device target → ⌘R              |

No third-party package dependencies — pure native Swift/SwiftUI.

---

## Source Structure (`MyLibrary/`)

### Entry Points

- `MyLibraryApp.swift` — `@main` app entry; initializes `LibraryStore` as `@StateObject`, renders `RootTabView`
- `RootTabView` (inside `MyLibraryApp.swift`) — Tab-based root with 3 tabs: Library, Lending, Settings

### Navigation

```
RootTabView (TabView)
├── Tab 1: LibraryView
│   └── NavigationStack → BookDetailView
│       ├── Sheet: EditBookView
│       └── Sheet: Lend action
│   └── Sheet: AddBookView
│       └── Sheet: BarcodeScannerView
├── Tab 2: LentBooksView
│   └── NavigationStack → BookDetailView
└── Tab 3: SettingsView
    └── File importer / exporter sheets
```

### Services (`Services/`)

| File                        | Purpose                                          |
| --------------------------- | ------------------------------------------------ |
| `BookLookupService.swift`   | Multi-API barcode/ISBN lookup with fallback chain (Google Books → Open Library → WorldCat) |
| `CSVBookImportService.swift` | Kindle and Audible CSV export parsing            |
| `LendingReminderService.swift` | UserNotifications permission and scheduling    |

### Views (`Views/`)

| File                     | Purpose                                              |
| ------------------------ | ---------------------------------------------------- |
| `LibraryView.swift`      | Main library with shelf grid and alphabetical list modes, search |
| `AddBookView.swift`      | Book addition via barcode scanner or manual entry, duplicate detection |
| `EditBookView.swift`     | Edit all book metadata, tag management               |
| `BookDetailView.swift`   | Hero cover image, metadata display, lending actions   |
| `LentBooksView.swift`    | Chronological list of currently lent books            |
| `SettingsView.swift`     | Reminder defaults, notification permissions, CSV import, backup/restore |
| `BarcodeScannerView.swift` | UIViewControllerRepresentable AVFoundation camera wrapper |
| `CoverArtView.swift`     | AsyncImage cover display with gradient fallback       |

### Models (`Models/`)

- `Book.swift` — Core data model with UUID, title, author, barcode, ISBN, genre (12-value enum), format (Physical/Digital), series info, tags, notes, lending state
- `LibraryBackupDocument.swift` — `FileDocument` conformance for iOS file export/import

### State Management (`Stores/`)

- **Pattern**: Single `ObservableObject` store injected via `@EnvironmentObject`
- **LibraryStore.swift** — `@Published var books: [Book]` with auto-persistence to JSON
  - Thread-safe add/update/remove operations
  - Deduplication on bulk import (by ISBN, barcode, or title+author)
  - Automatic sorting by title then author
  - Backup/restore data export

### Theme (`Theme/`)

- `LibraryTheme.swift` — Static color palette (accent red, paper cream, shelf brown, dark/light text), background gradient, forced light color scheme

---

## Configuration

### XcodeGen (`project.yml`)

- Target: `MyLibrary` (iOS application)
- Bundle ID: `com.harleyludwig.MyLibrary`
- Deployment target: iOS 17.0
- Device family: iPhone only
- Swift version: 5.0
- Camera permission configured (NSCameraUsageDescription)
- Auto-generated Info.plist, launch screen, scene manifest

### System Frameworks

| Framework              | Purpose                          |
| ---------------------- | -------------------------------- |
| SwiftUI                | UI framework                     |
| Foundation             | Core utilities, JSON, networking |
| AVFoundation           | Camera barcode scanning          |
| UserNotifications      | Lending reminders                |
| UniformTypeIdentifiers | File type handling               |
| Combine                | Via ObservableObject reactivity   |

---

## Key Architectural Patterns

### Observable Store + Environment Injection

Single `LibraryStore` instance created as `@StateObject` in the app entry point and passed down via `@EnvironmentObject`. All views read and mutate the shared book collection through this store.

### Multi-API Fallback Chain

`BookLookupService` queries APIs in priority order: Google Books → Open Library → WorldCat. Each stage has timeout handling (8s), retry logic for 429/5xx errors, and ISBN-10 ↔ ISBN-13 conversion. Cover images are validated with HTTP HEAD requests.

### Tab + NavigationStack + Sheet Composition

Root navigation uses `TabView` with three tabs. Each tab manages its own `NavigationStack` for drill-down navigation. Modal operations (add, edit, scan) use SwiftUI `.sheet()` presentation.

### Auto-Persistence

`LibraryStore` auto-saves the books array to a JSON file in the app documents directory whenever the `@Published` property changes, with a loading guard to prevent write-during-load race conditions.

---

## External Integrations

| Integration             | Purpose                        | Location                          |
| ----------------------- | ------------------------------ | --------------------------------- |
| Google Books API        | Primary book metadata + covers | `Services/BookLookupService.swift` |
| Open Library API        | Fallback ISBN lookup + covers  | `Services/BookLookupService.swift` |
| Open Library Search API | Book discovery by metadata     | `Services/BookLookupService.swift` |
| WorldCat Classify API   | Secondary ISBN validation      | `Services/BookLookupService.swift` |
| AVFoundation            | Barcode scanning (EAN-8, EAN-13, UPC-E, Code-39, Code-128) | `Views/BarcodeScannerView.swift` |
| UserNotifications       | Lending reminder scheduling    | `Services/LendingReminderService.swift` |

---

## Maintenance

### When to Update This File

- New directory added to `MyLibrary/`
- New service, view, or model added
- Build configuration changed in `project.yml`
- New external API integrated
- Architectural pattern introduced

### Verification Commands

```bash
# Verify structure matches documentation
ls MyLibrary/
ls MyLibrary/Views/
ls MyLibrary/Models/
ls MyLibrary/Services/
ls MyLibrary/Stores/
ls MyLibrary/Theme/

# Check XcodeGen config
cat project.yml
```

### Sync Checklist

- [ ] View listings match `MyLibrary/Views/`
- [ ] Service listings match `MyLibrary/Services/`
- [ ] Model listings match `MyLibrary/Models/`
- [ ] XcodeGen config matches `project.yml`
- [ ] External integrations are current
- [ ] Statistics are approximate but reasonable

---

> **Note**: This document is a navigation aid. Keep it accurate but don't over-document. Update when architecture changes, not for every file addition.
