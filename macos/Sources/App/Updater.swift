import Foundation
import Combine
import Sparkle

@MainActor
final class Updater: ObservableObject {
    private let controller: SPUStandardUpdaterController
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
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        if startingUpdater { controller.startUpdater() }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
