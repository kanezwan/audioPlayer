import SwiftUI

@main
struct audioPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 650)
    }
}
