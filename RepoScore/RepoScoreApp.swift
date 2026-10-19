import SwiftUI

@main
struct RepoScoreApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            LibraryView(store: library)
        }
    }
}
