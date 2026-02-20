# My Library (iOS)

My Library is a SwiftUI iOS app for managing a personal book collection.

## Features
- Barcode scan with iPhone camera.
- Barcode/ISBN lookup for title, author, genre hint, and cover image.
- Manual book entry fallback.
- Search by title, author, genre, ISBN, or barcode.
- Book metadata:
  - Genre
  - Physical or digital format
  - Series info (name + number)
  - Cover image URL
- Lending flow:
  - Mark book as lent
  - Track who borrowed it and when
  - Mark returned
- Colorful, library-inspired UI.

## Project Setup
1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed.
2. Generate the project:
   ```bash
   xcodegen generate
   ```
3. Open `MyLibrary.xcodeproj` in Xcode.
4. Select an iPhone device or simulator and run.

## Notes
- Camera scanning requires permission (`NSCameraUsageDescription` already configured).
- Book lookup uses Google Books public API via `URLSession`.
- Local data is persisted to app documents as JSON (`library_books.json`).
