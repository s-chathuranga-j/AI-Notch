import Darwin
import Foundation

enum ClaudeTokenRenewal {
    static func run(profile: ClaudeProfile) async throws -> Bool {
        let service = profile.keychainService
        guard let stamp = KeychainItem.modifiedAt(service: service) else { return false }
        let environment = ProcessInfo.processInfo.environment
        let directories = [ClaudeProfile.homeDirectory.appendingPathComponent(".local/bin").path,
                           "/opt/homebrew/bin", "/usr/local/bin"]
            + (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        guard let executable = directories.filter({ $0.hasPrefix("/") })
            .map({ URL(fileURLWithPath: $0).appendingPathComponent("claude") })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else { return false }

        return try await run(profile: profile, executable: executable, timeout: .seconds(12)) {
            KeychainItem.modifiedAt(service: service).map { $0 > stamp } ?? false
        }
    }

    static func run(profile: ClaudeProfile, executable: URL, timeout: Duration,
                    didRenew: () -> Bool) async throws -> Bool {
        try Task.checkCancellation()
        if didRenew() { return true }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard (try? FileManager.default.createDirectory(at: directory,
                                                        withIntermediateDirectories: false)) != nil
        else { return false }
        defer { try? FileManager.default.removeItem(at: directory) }

        // Claude's interactive startup needs a TTY. A PTY supplies one without Terminal.app.
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return false }
        let terminal = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        defer { close(master) }
        guard fcntl(master, F_SETFD, FD_CLOEXEC) != -1,
              fcntl(slave, F_SETFD, FD_CLOEXEC) != -1,
              fcntl(master, F_SETFL, O_NONBLOCK) != -1 else { return false }

        var environment = ProcessInfo.processInfo.environment
        // Passing even ~/.claude explicitly selects a different Keychain entry.
        environment["CLAUDE_CONFIG_DIR"] = profile.slug.map { _ in profile.configDirectory.path }
        environment["TERM"] = "xterm-256color"
        for name in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN",
                     "ANTHROPIC_BASE_URL", "ANTHROPIC_PROFILE", "CLAUDE_CODE_USE_BEDROCK",
                     "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "CLAUDECODE"] {
            environment.removeValue(forKey: name)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--safe-mode", "--tools", ""]
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = terminal
        process.standardOutput = terminal
        process.standardError = terminal
        do {
            try process.run()
        } catch {
            return false
        }
        try? terminal.close()

        let deadline = ContinuousClock.now.advanced(by: timeout)
        var output = [UInt8](repeating: 0, count: 16_384)
        while process.isRunning && ContinuousClock.now < deadline && !Task.isCancelled {
            // Drain the PTY so startup can't block on output. It can contain account details.
            _ = read(master, &output, output.count)
            if didRenew() { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        let renewed = didRenew()
        if process.isRunning {
            process.terminate()
            try? await Task.sleep(for: .milliseconds(250))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        try Task.checkCancellation()
        return renewed
    }
}
