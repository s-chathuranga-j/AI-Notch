import Combine

/// Uses the same account boundary as usage polling. Disabled monitors neither
/// start nor retain session details; other accounts continue independently.
@MainActor
final class ActivityMonitorController {
    private let monitors: [String: any AgentActivityMonitor]
    private(set) var active: Set<String> = []

    init(monitors: [String: any AgentActivityMonitor]) { self.monitors = monitors }

    func apply(disconnected: Set<String>, demo: Bool = false) {
        let wanted = demo ? [] : Set(monitors.keys).subtracting(disconnected)
        for id in active.subtracting(wanted) { monitors[id]?.stop() }
        let starting = wanted.subtracting(active)
        active = wanted
        for id in starting { monitors[id]?.start() }
    }

    var isBusy: Bool {
        active.contains { id in monitors[id]?.sessions.contains { $0.state == .busy } == true }
    }

    func stop() {
        for id in active { monitors[id]?.stop() }
        active = []
    }
}
