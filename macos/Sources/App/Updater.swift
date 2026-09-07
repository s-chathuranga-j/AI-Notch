import Foundation
import Combine

/// Build information for this independent local distribution.
/// No updater is included until AI Notch has its own signed release feed.
@MainActor
final class Updater: ObservableObject {
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
