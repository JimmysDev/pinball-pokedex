import SwiftUI

@main
struct PinballPokedexApp: App {
    @StateObject private var store = SaveStore()
    @StateObject private var live = LiveBridge()

    var body: some Scene {
        WindowGroup("Pinball Pokédex") {
            ContentView()
                .environmentObject(store)
                .environmentObject(live)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 980, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Save File…") { store.chooseFile() }
                    .keyboardShortcut("o")
                Button("Reload") { store.reloadNow() }
                    .keyboardShortcut("r")
            }
        }
    }
}
