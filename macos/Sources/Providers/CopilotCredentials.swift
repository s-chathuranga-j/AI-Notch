import Foundation
import os

/// The GitHub token behind a Copilot subscription, borrowed from the GitHub
/// CLI.
///
/// Copilot has no desktop app of its own to borrow a session from, and the
/// VS Code sign-in is stored in ways this app has no business reading. What
/// the Mac usually does have is `gh`, signed in with `gh auth login` — and it
/// will hand its own token to `gh auth token` without a prompt, because the
/// keychain item is gh's and gh is the one reading it. So that is what this
/// asks, the same way the Windows build does.
///
/// Two sources, in order:
///
/// 1. **`COPILOT_GITHUB_TOKEN`** in the app's environment. The escape hatch
///    for when GitHub will not accept the CLI's token on the quota endpoint;
///    read as-is, never written anywhere.
/// 2. **The GitHub CLI**, `gh auth token --hostname github.com`. The token
///    comes back on stdout and nowhere else: it is never passed as an
///    argument, where `ps` could see it, and stderr is discarded rather than
///    logged, because gh's diagnostics can quote credentials.
enum CopilotCredentials {
    struct Credential: Equatable {
        let token: String
        /// Where the token came from, for the settings row.
        let source: String
    }

    static let environmentVariable = "COPILOT_GITHUB_TOKEN"
    static let cliSource = "GitHub CLI"
    static let environmentSource = "environment"

    // MARK: Finding gh

    /// Where to look for the binary, in order: Homebrew on Apple silicon and
    /// Intel, the installer's location, then whatever `PATH` the app was
    /// launched with — which, from Finder, is very little.
    static func candidatePaths(home: String = NSHomeDirectory(),
                               path: String? = ProcessInfo.processInfo.environment["PATH"]) -> [URL] {
        var directories = ["/opt/homebrew/bin", "/usr/local/bin",
                           (home as NSString).appendingPathComponent(".local/bin")]
        for entry in (path ?? "").split(separator: ":") where !entry.isEmpty {
            let directory = String(entry)
            if !directories.contains(directory) { directories.append(directory) }
        }
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent("gh") }
    }

    static func executable(fileManager: FileManager = .default) -> URL? {
        candidatePaths().first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    // MARK: Reading the token

    /// `executable` is a parameter so a test can point this at a fake gh — or
    /// at nothing — instead of the one installed on the machine running it.
    static func load(environment: [String: String] = ProcessInfo.processInfo.environment,
                     executable: URL? = executable(),
                     cancellation: CodexBridge.ProcessCancellation = .init()) throws -> Credential {
        if let token = environment[environmentVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return Credential(token: token, source: environmentSource)
        }
        guard let gh = executable else {
            throw UsageProviderError.nothingMetered(
                "Install the GitHub CLI (gh) and sign in, or launch with COPILOT_GITHUB_TOKEN set")
        }
        return Credential(token: try token(fromCLI: gh, cancellation: cancellation), source: cliSource)
    }

    /// Bounded, so a misbehaving binary cannot fill memory through the pipe.
    static let maxOutputBytes = 16 * 1024

    /// One `gh auth token` run, with the cancellation reaching the process.
    ///
    /// Blocking: call it off the actor, the way `CodexBridge` is called.
    static func token(fromCLI executable: URL, timeout: TimeInterval = 10,
                      cancellation: CodexBridge.ProcessCancellation = .init()) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["auth", "token", "--hostname", "github.com"]
        var environment = ProcessInfo.processInfo.environment
        // A token lookup should not be the moment gh checks for its own
        // updates, and colour codes have no business in a token.
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        environment["NO_COLOR"] = "1"
        environment["GH_PROMPT_DISABLED"] = "1"
        process.environment = environment
        let output = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        // Never read, never logged: gh's error text can quote its own state.
        process.standardError = FileHandle.nullDevice
        do {
            try cancellation.run(process)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.usage.error("copilot: the GitHub CLI could not be launched")
            throw UsageProviderError.needsAuth
        }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer {
            watchdog.cancel()
            if process.isRunning { process.terminate() }
        }

        var buffer = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            if buffer.count > maxOutputBytes {
                process.terminate()
                Log.usage.error("copilot: the GitHub CLI answered with more than a token")
                throw UsageProviderError.needsAuth
            }
        }
        process.waitUntilExit()

        let token = String(decoding: buffer, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationReason == .exit, process.terminationStatus == 0, !token.isEmpty else {
            // Signed out, or stopped by the watchdog. The exit status is safe
            // to log; the output is not.
            Log.usage.notice("copilot: gh auth token exited \(process.terminationStatus)")
            throw UsageProviderError.needsAuth
        }
        return token
    }

    // MARK: Whose account

    /// `~/.config/gh/hosts.yml`, or where `GH_CONFIG_DIR` points.
    static var hostsFileURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let directory = environment["GH_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : ($0 as NSString).appendingPathComponent("gh") }
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config/gh")
        return URL(fileURLWithPath: directory).appendingPathComponent("hosts.yml")
    }

    /// The login gh is signed in as on github.com, for the settings row.
    ///
    /// Deliberately the least the file has to offer. `hosts.yml` can also hold
    /// an `oauth_token` when gh's keychain storage is off, and this never
    /// reads that line: the token is asked of gh itself, so that gh — not a
    /// hand-rolled YAML reader — decides which credential is current. The
    /// file is read with a five-line parser rather than a YAML library
    /// because the two keys it needs are the two keys gh has always written:
    ///
    /// ```yaml
    /// github.com:
    ///     user: octocat
    ///     git_protocol: https
    /// ```
    static func login(hostsFile url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var inGitHub = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indented = line.first?.isWhitespace == true
            if !indented {
                // A new top-level host. Only github.com counts: Copilot's
                // quota endpoint is github.com's, whatever else gh knows.
                inGitHub = trimmed == "github.com:"
                continue
            }
            guard inGitHub, trimmed.hasPrefix("user:") else { continue }
            let value = trimmed.dropFirst("user:".count).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
