import SwiftUI

@main
struct KurtkodeApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 760, minHeight: 480)
        }
        .commands { AppCommands() }

        // SwiftUI lists these in the Window menu itself (with these shortcuts).
        Window("Models", id: "models") {
            ModelsView()
                .environment(app)
        }
        .defaultSize(width: 720, height: 640)
        .keyboardShortcut("m", modifiers: [.command, .shift])

        Window("Spending", id: "spending") {
            SpendingView()
                .environment(app)
        }
        .defaultSize(width: 1040, height: 520)

        Window("Debug", id: "debug") {
            DebugView()
                .environment(app)
        }
        .defaultSize(width: 1240, height: 780)
        .keyboardShortcut("d", modifiers: [.command, .option])

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

extension FocusedValues {
    /// Starts a new chat in the focused window.
    @Entry var newChat: (@MainActor () -> Void)?
    /// Asks for a project folder and starts a chat in it.
    @Entry var openFolder: (@MainActor () -> Void)?
    /// Stops generation in the focused window's session.
    @Entry var stopGenerating: (@MainActor () -> Void)?
    /// Opens the find bar of the focused window's chat.
    @Entry var findInChat: (@MainActor () -> Void)?
    /// Puts the cursor in the focused window's chat search.
    @Entry var searchChats: (@MainActor () -> Void)?
}

struct AppCommands: Commands {
    @FocusedValue(\.newChat) private var newChat
    @FocusedValue(\.openFolder) private var openFolder
    @FocusedValue(\.stopGenerating) private var stopGenerating
    @FocusedValue(\.findInChat) private var findInChat
    @FocusedValue(\.searchChats) private var searchChats
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .newItem) {
            Button("New Chat") { newChat?() }
                .keyboardShortcut("n")
                .disabled(newChat == nil)
            Button("Open Folder…") { openFolder?() }
                .keyboardShortcut("o")
                .disabled(openFolder == nil)
        }
        CommandGroup(replacing: .newItem) {
            // Keep a way to open another window (D14: one agent per window).
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("Chat") {
            Button("Stop Generating") { stopGenerating?() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(stopGenerating == nil)
            Divider()
            Button("Find in Chat") { findInChat?() }
                .keyboardShortcut("f")
                .disabled(findInChat == nil)
            Button("Search All Chats") { searchChats?() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(searchChats == nil)
        }
    }
}
