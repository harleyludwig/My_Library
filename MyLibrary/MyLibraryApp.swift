import SwiftUI

@main
struct MyLibraryApp: App {
    @StateObject private var libraryStore = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(libraryStore)
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }

            LentBooksView()
                .tabItem {
                    Label("Lending", systemImage: "person.2.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(LibraryTheme.accent)
        .preferredColorScheme(.light)
    }
}
