import Foundation

/// Which window a provider's ring stands for.
///
/// The provider's own headline is the default for the reasons spelled out on
/// `ProviderSnapshot.headline`: it does not change subject between refreshes.
/// But someone on a plan where the weekly limit is the one that bites wants the
/// ring to watch that one, and that is a choice they can make knowingly.
enum RingChoice: Equatable, Hashable {
    /// The provider's declared headline — for Claude, the session.
    case provider
    /// Whichever window is closest to its limit right now. This one *does*
    /// change subject, which is the point of choosing it.
    case closest
    /// A named window. If the provider stops reporting it, or reports it
    /// without a percentage, the ring falls back to the provider's headline
    /// rather than going blank.
    case window(String)

    init(rawValue: String?) {
        switch rawValue {
        case "closest"?: self = .closest
        case let value? where value.hasPrefix("window:"):
            self = .window(String(value.dropFirst("window:".count)))
        default: self = .provider
        }
    }

    var rawValue: String {
        switch self {
        case .provider:        return "auto"
        case .closest:         return "closest"
        case .window(let id):  return "window:\(id)"
        }
    }
}

extension ProviderSnapshot {
    /// The same reading with its ring pointed where the user chose.
    func applying(_ choice: RingChoice) -> ProviderSnapshot {
        var copy = self
        switch choice {
        case .provider:
            break
        case .closest:
            let metered = windows.filter { $0.usedFraction != nil }
            if let top = metered.max(by: { ($0.usedFraction ?? 0) < ($1.usedFraction ?? 0) }) {
                copy.headlineID = top.id
            }
        case .window(let id):
            // Only a window with a reading: one reported without a percentage
            // would draw an empty ring, so it falls back as a missing one does.
            if windows.contains(where: { $0.id == id && $0.usedFraction != nil }) {
                copy.headlineID = id
            }
        }
        return copy
    }
}
