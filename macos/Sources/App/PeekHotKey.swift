import Carbon.HIToolbox
import Foundation

/// The keyboard shortcuts the peek can be bound to.
///
/// A short list rather than a recorder: each of these is free on a stock Mac,
/// and a recorder is a lot of interface for a key most people set once.
enum PeekShortcut: String, CaseIterable, Identifiable {
    case controlOptionN
    case controlOptionU
    case controlOptionSpace
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlOptionN:     return "⌃⌥N"
        case .controlOptionU:     return "⌃⌥U"
        case .controlOptionSpace: return "⌃⌥Space"
        case .off:                return "Off"
        }
    }

    /// Virtual key code and Carbon modifier mask, or nil for off.
    var keys: (code: UInt32, modifiers: UInt32)? {
        let mods = UInt32(controlKey | optionKey)
        switch self {
        case .controlOptionN:     return (UInt32(kVK_ANSI_N), mods)
        case .controlOptionU:     return (UInt32(kVK_ANSI_U), mods)
        case .controlOptionSpace: return (UInt32(kVK_Space), mods)
        case .off:                return nil
        }
    }
}

/// A system-wide shortcut that brings the notch out for a look, from any app.
///
/// Carbon's hot keys rather than an event monitor: they need no Accessibility
/// permission, and they fire only for the one combination asked for instead of
/// letting the app see every key pressed.
final class PeekHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Binds the shortcut. False when another app already holds it, so
    /// Settings can say so instead of the key silently doing nothing.
    @discardableResult
    func register(_ shortcut: PeekShortcut) -> Bool {
        unregister()
        guard let keys = shortcut.keys else { return true }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x414E_4F54), id: 1)   // 'ANOT'
        let status = RegisterEventHotKey(keys.code, keys.modifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { hotKey = nil }
        return status == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    fileprivate func fire() { action() }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // Unretained: the handler is removed in `deinit`, before the object
        // it points at can go away.
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<PeekHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.fire() }
            return noErr
        }, 1, &spec, context, &handler)
    }
}
