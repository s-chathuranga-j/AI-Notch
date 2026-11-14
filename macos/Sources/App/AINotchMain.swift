import SwiftUI

@main
enum AINotchEntryPoint {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.dropFirst().first == "--claude-status-line" {
            if args.count == 3 { ClaudeStatusLineProvider.collect(providerID: args[2]) }
            return
        }
        AINotchMain.main()
    }
}

struct AINotchMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The notch is the UI; the panel is put up by the delegate. This scene
        // exists only because `App` needs one.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.showSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
