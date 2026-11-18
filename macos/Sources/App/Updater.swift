import Foundation
import Combine
import Sparkle
import AppKit
import Security

@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
    )
    private var windowObserver: AnyCancellable?
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            if controller.updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
        }
    }

    // Tests and previews must opt in before any network checks can start.
    init(startingUpdater: Bool = false) {
        super.init()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        windowObserver = NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] notification in
                guard let window = notification.object as? NSWindow,
                      window.identifier?.rawValue == "SUUpdateAlert",
                      let content = window.contentView else { return }
                self?.updateMessage(in: content)
            }
        if startingUpdater { controller.startUpdater() }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        // A bundle replaced while running can pass disk verification but fail authd's process check.
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess else {
            throw NSError(domain: "com.fourforge.ainotch.updater", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Restart AI Notch before updating.",
                NSLocalizedRecoverySuggestionErrorKey:
                    "Quit AI Notch and reopen it from Applications, then choose Check for Updates again. macOS could not verify this running copy."
            ])
        }
    }

    private func updateMessage(in view: NSView) {
        if let field = view as? NSTextField {
            field.stringValue = Self.updateMessage(field.stringValue)
        }
        for child in view.subviews { updateMessage(in: child) }
    }

    static func updateMessage(_ message: String) -> String {
        message.replacingOccurrences(of: "available—you have", with: "available. You have")
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
