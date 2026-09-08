import XCTest
@testable import AINotch

/// Guards the shape of `GET /copilot_internal/user`. It is GitHub's internal
/// entitlement endpoint, not a published API, so these are the tests that will
/// fail first if it changes — and they double as the record of what the
/// Windows build agreed to read, since both apps parse the same answer.
final class CopilotQuotaResponseTests: XCTestCase {
    private func parse(_ json: String) throws -> CopilotUsage.Payload {
        try CopilotUsage.parse(Data(json.utf8))
    }

    /// The shape VS Code's quota banner reads: a plan-wide reset, one limited
    /// quota and two unlimited ones.
    private let live = """
    { "copilot_plan": "individual_pro", "token_based_billing": false,
      "quota_reset_date_utc": "2026-10-01T00:00:00Z",
      "quota_snapshots": {
        "premium_interactions": { "entitlement": 300, "remaining": 225,
                                  "percent_remaining": 75, "unlimited": false },
        "chat": { "unlimited": true },
        "completions": { "percent_remaining": 100 } } }
    """

    func testRemainingBecomesUsedAndUnlimitedIsKeptAsSuch() throws {
        let payload = try parse(live)
        XCTAssertEqual(payload.plan, "individual_pro")
        XCTAssertEqual(payload.windows.map(\.id), ["premium", "chat", "completions"])
        XCTAssertEqual(payload.windows[0].label, "Premium requests")
        XCTAssertEqual(payload.windows[0].usedFraction ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertTrue(payload.windows[1].isUnlimited)
        XCTAssertNil(payload.windows[1].usedFraction)
        XCTAssertEqual(payload.windows[2].usedFraction ?? -1, 0, accuracy: 0.0001)
    }

    /// The ring means the first quota that has a number, not the first row.
    func testTheHeadlineIsTheFirstLimitedQuota() throws {
        XCTAssertEqual(try parse(live).headlineID, "premium")
        let unlimitedFirst = """
        { "quota_snapshots": { "premium_interactions": { "unlimited": true },
                               "chat": { "percent_remaining": 40 } } }
        """
        XCTAssertEqual(try parse(unlimitedFirst).headlineID, "chat")
    }

    /// Every quota unlimited is a reading — the cell shows ∞ — not a failure.
    func testAllUnlimitedHasWindowsButNoHeadline() throws {
        let payload = try parse(#"{"quota_snapshots":{"chat":{"unlimited":true},"completions":{"unlimited":true}}}"#)
        XCTAssertEqual(payload.windows.count, 2)
        XCTAssertNil(payload.headlineID)
        let snapshot = ProviderSnapshot(id: "copilot", displayName: "Copilot", glyph: .copilot,
                                        fidelity: .official, status: .ok,
                                        windows: payload.windows, headlineID: payload.headlineID)
        XCTAssertEqual(snapshot.headlineText, "∞")
        XCTAssertNil(snapshot.ringFraction)
    }

    func testThePlanWideResetAppliesToQuotasWithoutTheirOwn() throws {
        let windows = try parse(live).windows
        XCTAssertEqual(windows[0].resetsAt?.timeIntervalSince1970 ?? -1, 1_790_812_800, accuracy: 0.001)
        XCTAssertEqual(windows[1].resetsAt, windows[0].resetsAt, "unlimited rows still say when the plan resets")
    }

    /// A quota's own reset wins, and arrives as seconds since the epoch.
    func testAQuotaResetTimestampWinsOverThePlanDate() throws {
        let json = """
        { "quota_reset_date": "2026-10-01T00:00:00Z",
          "quota_snapshots": { "chat": { "percent_remaining": 50, "quota_reset_at": 1790000000 } } }
        """
        XCTAssertEqual(try parse(json).windows[0].resetsAt?.timeIntervalSince1970 ?? -1,
                       1_790_000_000, accuracy: 0.001)
    }

    func testResetDatesAcceptADateWithoutATimeAndRejectNonsense() throws {
        XCTAssertEqual(CopilotUsage.date("2026-10-01")?.timeIntervalSince1970 ?? -1,
                       1_790_812_800, accuracy: 0.001)
        XCTAssertNotNil(CopilotUsage.date("2026-10-01T00:00:00.000Z"))
        XCTAssertNil(CopilotUsage.date("invalid"))
        XCTAssertNil(CopilotUsage.date(0), "zero is gh's way of saying no date")
        XCTAssertNil(CopilotUsage.date(true))
        let noReset = try parse(#"{"quota_reset_date":"invalid","quota_snapshots":{"chat":{"percent_remaining":50}}}"#)
        XCTAssertNil(noReset.windows[0].resetsAt)
    }

    /// Credit-billed plans meter AI credits where others meter premium
    /// requests. The flag lives on the plan or on the quota, depending on
    /// the build that answered.
    func testCreditBillingRelabelsPremiumRequests() throws {
        let onPlan = try XCTUnwrap(try parse(#"{"token_based_billing":true,"quota_snapshots":{"premium_interactions":{"percent_remaining":0}}}"#).windows.first)
        XCTAssertEqual(onPlan.label, "AI credits")
        XCTAssertEqual(onPlan.usedFraction ?? -1, 1, accuracy: 0.0001)
        let onQuota = try parse(#"{"quota_snapshots":{"premium_interactions":{"percent_remaining":10,"token_based_billing":true},"chat":{"percent_remaining":10,"token_based_billing":true}}}"#)
        XCTAssertEqual(onQuota.windows.map(\.label), ["AI credits", "Chat"])
    }

    /// Nothing entitled is not a quota; drawing it would show "none used" of
    /// an allowance the account does not have.
    func testAZeroEntitlementIsNotARow() throws {
        XCTAssertTrue(try parse(#"{"quota_snapshots":{"chat":{"entitlement":0,"percent_remaining":0}}}"#).windows.isEmpty)
        XCTAssertTrue(try parse(#"{"quota_snapshots":{"chat":{"entitlement":"0","percent_remaining":0}}}"#).windows.isEmpty)
    }

    func testTheCountsAreUsedWhenThePercentageIsMissing() throws {
        let window = try XCTUnwrap(try parse(#"{"quota_snapshots":{"chat":{"entitlement":100,"remaining":25}}}"#).windows.first)
        XCTAssertEqual(window.usedFraction ?? -1, 0.75, accuracy: 0.0001)
    }

    /// Malformed numbers drop the row, never the reading; the wrong type is
    /// not a percentage we are willing to read.
    func testMalformedQuotasAreDroppedWithoutInventingUsage() throws {
        for json in [
            "{}",
            #"{"quota_snapshots":{}}"#,
            #"{"quota_snapshots":{"premium_interactions":{"percent_remaining":"70"}}}"#,
            #"{"quota_snapshots":{"chat":{"percent_remaining":true}}}"#,
            #"{"quota_snapshots":{"chat":{"entitlement":100}}}"#,
            #"{"quota_snapshots":{"chat":{"entitlement":100,"remaining":-1}}}"#,
            #"{"quota_snapshots":{"chat":"unlimited"}}"#,
            #"{"quota_snapshots":{"unknown":{"percent_remaining":10}}}"#
        ] {
            XCTAssertTrue(try parse(json).windows.isEmpty, json)
        }
    }

    /// 0 and 1 bridge to Bool as readily as to Double; both are still numbers
    /// here, and a spent quota is a reading, not a missing one.
    func testZeroAndOneAreNumbersNotBooleans() throws {
        XCTAssertEqual(try parse(#"{"quota_snapshots":{"chat":{"percent_remaining":0}}}"#).windows.first?.usedFraction, 1)
        XCTAssertEqual(try parse(#"{"quota_snapshots":{"chat":{"percent_remaining":1}}}"#).windows.first?.usedFraction ?? -1, 0.99, accuracy: 0.0001)
        XCTAssertEqual(try parse(#"{"quota_snapshots":{"chat":{"entitlement":1,"remaining":0}}}"#).windows.first?.usedFraction, 1)
        XCTAssertTrue(try parse(#"{"quota_snapshots":{"chat":{"percent_remaining":false}}}"#).windows.isEmpty)
    }

    func testAPercentageOutsideTheRangeIsClamped() throws {
        XCTAssertEqual(try parse(#"{"quota_snapshots":{"chat":{"percent_remaining":140}}}"#).windows[0].usedFraction ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(try parse(#"{"quota_snapshots":{"chat":{"percent_remaining":-5}}}"#).windows[0].usedFraction ?? -1, 1, accuracy: 0.0001)
    }

    func testANonObjectBodyIsABadResponse() {
        XCTAssertThrowsError(try parse("[1,2,3]"))
        XCTAssertThrowsError(try parse("not json"))
    }
}

/// `isUnlimited` was added for Copilot; the archive and the tooltip both have
/// to keep making sense around it.
final class LimitWindowUnlimitedTests: XCTestCase {
    func testAnUnlimitedWindowSaysSoInsteadOfNoReading() {
        XCTAssertEqual(LimitWindow(id: "chat", label: "Chat", isUnlimited: true).summary, "Unlimited")
        XCTAssertEqual(LimitWindow(id: "chat", label: "Chat").summary, "No reading")
    }

    /// Archived readings written before the field existed decode as limited.
    func testAnArchivedWindowWithoutTheKeyDecodesAsLimited() throws {
        let legacy = #"{"id":"session","label":"Current session","usedFraction":0.5}"#
        let window = try JSONDecoder().decode(LimitWindow.self, from: Data(legacy.utf8))
        XCTAssertFalse(window.isUnlimited)
        XCTAssertEqual(window.usedFraction, 0.5)
    }

    func testTheFlagRoundTripsThroughTheArchiveEncoding() throws {
        let original = LimitWindow(id: "chat", label: "Chat", resetsAt: Date(timeIntervalSince1970: 1_790_000_000), isUnlimited: true)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(LimitWindow.self, from: data), original)
    }
}

/// The token is borrowed from the GitHub CLI or the environment, and neither
/// path may leak it. All of these run against fixtures and fake executables,
/// never against the real gh.
final class CopilotCredentialsTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopilotCredentialsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// A shell script standing in for gh, so what it prints and how it exits
    /// are the test's to choose.
    private func fakeCLI(_ script: String) throws -> URL {
        let url = scratch.appendingPathComponent("gh")
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testTheEnvironmentTokenWinsWithoutRunningAnything() throws {
        let credential = try CopilotCredentials.load(environment: ["COPILOT_GITHUB_TOKEN": " synthetic-env-token \n"])
        XCTAssertEqual(credential, .init(token: "synthetic-env-token", source: "environment"))
    }

    /// A blank falls through to gh — here, to no gh at all — and is never
    /// returned as a credential. The real binary is deliberately kept out of
    /// this: a test that ran it would be reading the developer's own login.
    func testAnEmptyEnvironmentTokenDoesNotCount() throws {
        XCTAssertThrowsError(try CopilotCredentials.load(environment: ["COPILOT_GITHUB_TOKEN": "  "],
                                                          executable: nil)) { error in
            guard case UsageProviderError.nothingMetered = error else { return XCTFail("got \(error)") }
        }
    }

    func testTheEnvironmentTokenIsUsedBeforeTheCLIEvenWhenBothExist() throws {
        let gh = try fakeCLI("echo cli-token")
        let credential = try CopilotCredentials.load(environment: ["COPILOT_GITHUB_TOKEN": "env-token"], executable: gh)
        XCTAssertEqual(credential.token, "env-token")
        XCTAssertEqual(try CopilotCredentials.load(environment: [:], executable: gh),
                       .init(token: "cli-token", source: "GitHub CLI"))
    }

    func testTheCLITokenIsReadFromStandardOutputOnly() throws {
        let gh = try fakeCLI(#"echo "synthetic-cli-token"; echo "diagnostic that must be dropped" 1>&2"#)
        XCTAssertEqual(try CopilotCredentials.token(fromCLI: gh), "synthetic-cli-token")
    }

    /// The token is asked *of* gh, not passed *to* it — an argument shows in
    /// `ps`, stdout does not.
    func testTheCLIIsAskedWithFixedArgumentsAndNoSecret() throws {
        let recorder = scratch.appendingPathComponent("args.txt")
        let gh = try fakeCLI(#"echo "$@" > "\#(recorder.path)"; echo tok"#)
        _ = try CopilotCredentials.token(fromCLI: gh)
        XCTAssertEqual(try String(contentsOf: recorder, encoding: .utf8).trimmingCharacters(in: .newlines),
                       "auth token --hostname github.com")
    }

    func testASignedOutCLIReadsAsNeedingAuth() throws {
        let gh = try fakeCLI(#"echo "not logged in" 1>&2; exit 1"#)
        XCTAssertThrowsError(try CopilotCredentials.token(fromCLI: gh)) { error in
            guard case UsageProviderError.needsAuth = error else { return XCTFail("got \(error)") }
        }
        let silent = try fakeCLI("exit 0")
        XCTAssertThrowsError(try CopilotCredentials.token(fromCLI: silent))
    }

    func testAHangingCLIIsStoppedByTheWatchdog() throws {
        let gh = try fakeCLI("sleep 30")
        let started = Date()
        XCTAssertThrowsError(try CopilotCredentials.token(fromCLI: gh, timeout: 0.5))
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testCancellationBeforeLaunchNeverRunsTheCLI() throws {
        let marker = scratch.appendingPathComponent("ran")
        let gh = try fakeCLI(#"touch "\#(marker.path)"; echo tok"#)
        let cancellation = CodexBridge.ProcessCancellation()
        cancellation.cancel()
        XCTAssertThrowsError(try CopilotCredentials.token(fromCLI: gh, cancellation: cancellation)) { error in
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testTheCLIIsLookedForInTheUsualPlacesThenOnPath() {
        let paths = CopilotCredentials.candidatePaths(home: "/Users/test", path: "/custom/bin:/opt/homebrew/bin::/other")
            .map(\.path)
        XCTAssertEqual(paths, ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/Users/test/.local/bin/gh",
                               "/custom/bin/gh", "/other/gh"])
        XCTAssertEqual(CopilotCredentials.candidatePaths(home: "/Users/test", path: nil).count, 3)
    }

    // MARK: hosts.yml

    private func hosts(_ yaml: String) throws -> URL {
        let url = scratch.appendingPathComponent("hosts.yml")
        try Data(yaml.utf8).write(to: url)
        return url
    }

    func testTheLoginComesFromTheGitHubBlock() throws {
        let file = try hosts("""
        ghe.example.invalid:
            user: someone-else
            git_protocol: ssh
        github.com:
            users:
                octocat:
                    oauth_token: SYNTHETIC-MUST-NOT-BE-READ
            git_protocol: https
            user: octocat
            oauth_token: SYNTHETIC-MUST-NOT-BE-READ
        """)
        XCTAssertEqual(CopilotCredentials.login(hostsFile: file), "octocat")
    }

    func testOtherHostsAndMissingFilesGiveNoLogin() throws {
        XCTAssertNil(CopilotCredentials.login(hostsFile: try hosts("ghe.example.invalid:\n    user: someone\n")))
        XCTAssertNil(CopilotCredentials.login(hostsFile: try hosts("github.com:\n    git_protocol: https\n")))
        XCTAssertNil(CopilotCredentials.login(hostsFile: scratch.appendingPathComponent("absent.yml")))
    }

    func testAQuotedLoginIsUnquoted() throws {
        XCTAssertEqual(CopilotCredentials.login(hostsFile: try hosts("github.com:\n  user: \"octo-cat\"\n")), "octo-cat")
    }
}

/// The provider end to end against a stubbed endpoint: what it sends, where,
/// and how each answer degrades.
final class CopilotProviderTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopilotProviderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        CopilotStub.reset([])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private static let payload = Data("""
    { "copilot_plan": "individual_pro", "quota_reset_date_utc": "2099-01-01T00:00:00Z",
      "quota_snapshots": { "premium_interactions": { "percent_remaining": 58 },
                           "chat": { "unlimited": true } } }
    """.utf8)

    /// A counter of credential reads, so a test can tell whether the provider
    /// went back to gh or served the held token.
    private final class TokenSource: @unchecked Sendable {
        var reads = 0
        var token = "synthetic-token"
        func load(_: CodexBridge.ProcessCancellation) throws -> CopilotCredentials.Credential {
            reads += 1
            return .init(token: token, source: "GitHub CLI")
        }
    }

    private func makeProvider(source: TokenSource = TokenSource(),
                              environment: [String: String] = [:]) -> CopilotProvider {
        let name = "CopilotProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return CopilotProvider(session: CopilotStub.session(),
                               archive: UsageArchive(defaults: defaults),
                               environment: environment,
                               hostsFile: scratch.appendingPathComponent("hosts.yml"),
                               loadCredentials: source.load)
    }

    func testAGoodAnswerBecomesAnOfficialSnapshotWithTheLimitedQuotaAsHeadline() async throws {
        CopilotStub.reset([.init(status: 200, body: Self.payload)])
        let provider = makeProvider()
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertEqual(snapshot.id, "copilot")
        XCTAssertEqual(snapshot.fidelity, .official)
        XCTAssertEqual(snapshot.headlineID, "premium")
        XCTAssertEqual(snapshot.usedFraction ?? -1, 0.42, accuracy: 0.0001)
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(provider.account()?.plan, "individual pro")
        XCTAssertEqual(provider.account()?.source, "GitHub CLI")
    }

    /// The whole privacy contract of the request, in one place: the fixed
    /// destination, the bearer header, and nothing else carrying the token.
    func testTheTokenGoesOnlyToTheFixedEndpointAsABearerHeader() async throws {
        CopilotStub.reset([.init(status: 200, body: Self.payload)])
        _ = try await makeProvider().fetchSnapshot()
        let request = try XCTUnwrap(CopilotStub.lastRequest)
        XCTAssertEqual(request.url, URL(string: "https://api.github.com/copilot_internal/user"))
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
        XCTAssertNil(request.httpBody)
        XCTAssertFalse(request.url!.absoluteString.contains("synthetic-token"))
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("AI-Notch/") ?? false)
    }

    func testOnlyTheExactGitHubAPIHostIsPermitted() {
        let hosts: Set<String> = ["api.github.com"]
        XCTAssertTrue(ProviderHTTP.permits(CopilotProvider.endpoint, hosts: hosts))
        for url in ["http://api.github.com/copilot_internal/user", "https://github.com/copilot_internal/user",
                    "https://api.github.com.evil.invalid/", "https://user:secret@api.github.com/",
                    "https://api.github.com:8443/"] {
            XCTAssertFalse(ProviderHTTP.permits(URL(string: url), hosts: hosts), url)
        }
    }

    /// The token is held between polls, so gh is not spawned once a minute.
    func testTheTokenIsHeldBetweenSuccessfulFetches() async throws {
        CopilotStub.reset([.init(status: 200, body: Self.payload), .init(status: 200, body: Self.payload)])
        let source = TokenSource()
        let provider = makeProvider(source: source)
        _ = try await provider.fetchSnapshot()
        _ = try await provider.fetchSnapshot()
        XCTAssertEqual(source.reads, 1)
        XCTAssertEqual(CopilotStub.requestCount, 2)
    }

    /// A refusal drops the held token so a fresh `gh auth login` is picked up.
    func testARefusalReadsAsNeedingAuthAndForgetsTheToken() async throws {
        CopilotStub.reset([.init(status: 401), .init(status: 200, body: Self.payload)])
        let source = TokenSource()
        let provider = makeProvider(source: source)
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected needsAuth")
        } catch UsageProviderError.needsAuth {}
        XCTAssertNil(provider.account(), "a refused token is not an account to show")
        _ = try await provider.fetchSnapshot()
        XCTAssertEqual(source.reads, 2, "the second fetch should have gone back to gh")
    }

    func testForbiddenIsAlsoARefusal() async {
        CopilotStub.reset([.init(status: 403)])
        do {
            _ = try await makeProvider().fetchSnapshot()
            XCTFail("expected needsAuth")
        } catch UsageProviderError.needsAuth {
        } catch { XCTFail("got \(error)") }
    }

    /// No quota endpoint for this account, and a body with nothing in it, are
    /// statements about the account — shown as such, never as a stale ring.
    func testMissingQuotasAreReportedNotInvented() async {
        for answer in [CopilotStub.Answer(status: 404), .init(status: 200, body: Data("{}".utf8))] {
            CopilotStub.reset([answer])
            do {
                _ = try await makeProvider().fetchSnapshot()
                XCTFail("expected nothingMetered for \(answer.status)")
            } catch UsageProviderError.nothingMetered {
            } catch { XCTFail("got \(error)") }
        }
    }

    func testAServerErrorIsABadResponseWithItsStatus() async {
        CopilotStub.reset([.init(status: 503)])
        do {
            _ = try await makeProvider().fetchSnapshot()
            XCTFail("expected badResponse")
        } catch UsageProviderError.badResponse(let status) {
            XCTAssertEqual(status, 503)
        } catch { XCTFail("got \(error)") }
    }

    /// After a 429 the next fetch is skipped without a request, on the shared
    /// back-off schedule.
    func testAThrottledAnswerBacksOffWithoutTouchingTheNetwork() async {
        CopilotStub.reset([.init(status: 429), .init(status: 200, body: Self.payload)])
        let provider = makeProvider()
        for _ in 0..<2 {
            do {
                _ = try await provider.fetchSnapshot()
                XCTFail("expected rateLimited")
            } catch UsageProviderError.rateLimited(let wait) {
                XCTAssertGreaterThan(wait, 0)
                XCTAssertLessThanOrEqual(wait, 60)
            } catch { XCTFail("got \(error)") }
        }
        XCTAssertEqual(CopilotStub.requestCount, 1)
    }

    /// Before any fetch, the row knows whose credential it would borrow from
    /// the prompt-free signs alone — and nothing more.
    func testTheAccountRowIsBuiltFromPromptFreeSignsBeforeAnyFetch() throws {
        XCTAssertNil(makeProvider().account())

        try Data("github.com:\n    user: octocat\n".utf8).write(to: scratch.appendingPathComponent("hosts.yml"))
        let viaCLI = makeProvider().account()
        XCTAssertEqual(viaCLI?.label, "octocat")
        XCTAssertEqual(viaCLI?.source, "GitHub CLI")
        XCTAssertNil(viaCLI?.plan)

        let viaEnvironment = makeProvider(environment: ["COPILOT_GITHUB_TOKEN": "synthetic"]).account()
        XCTAssertEqual(viaEnvironment?.source, "environment")
        XCTAssertNil(viaEnvironment?.label, "an environment token says nothing about who it belongs to")
    }

    func testForgettingTheCredentialClearsWhatTheRowKnew() async throws {
        CopilotStub.reset([.init(status: 200, body: Self.payload), .init(status: 200, body: Self.payload)])
        let source = TokenSource()
        let provider = makeProvider(source: source)
        _ = try await provider.fetchSnapshot()
        XCTAssertNotNil(provider.account())
        provider.forgetCachedCredential()
        XCTAssertNil(provider.account())
        _ = try await provider.fetchSnapshot()
        XCTAssertEqual(source.reads, 2)
    }

    func testCancellationDoesNotReachTheEndpoint() async {
        CopilotStub.reset([.init(status: 200, body: Self.payload)])
        let provider = makeProvider()
        let task = Task { try await provider.fetchSnapshot() }
        task.cancel()
        let result = await task.result
        if case .success = result { XCTFail("a cancelled fetch produced a snapshot") }
        XCTAssertEqual(CopilotStub.requestCount, 0)
    }
}

/// The mark is flattened from GitHub's own icon, so its geometry is pinned:
/// six loops inside the unit box, with the body carrying most of the ink.
final class CopilotGlyphTests: XCTestCase {
    func testTheOutlineHasTheSixLoopsOfTheIconInsideTheUnitBox() {
        let outline = GlyphOutline.copilot
        XCTAssertEqual(outline.count, 6, "body, face, two sockets, two pupils")
        for loop in outline {
            XCTAssertGreaterThanOrEqual(loop.count, 8)
            for point in loop {
                XCTAssertTrue(point.x >= -0.001 && point.x <= 1.001, "x \(point.x) outside the unit box")
                XCTAssertTrue(point.y >= -0.001 && point.y <= 1.001, "y \(point.y) outside the unit box")
            }
        }
    }

    func testTheMarkMatchesTheProviderGlyph() {
        XCTAssertEqual(ProviderGlyph.copilot.rawValue, "copilot")
        XCTAssertEqual(ProviderGlyph.copilot.outline, GlyphOutline.copilot)
        XCTAssertEqual(ProviderGlyph.copilot.assetName, "glyph-copilot")
        XCTAssertEqual(ProviderGlyph(rawValue: "copilot"), .copilot)
    }

    /// The first loop is the body, and it has to have ink or the cell renders
    /// an empty ring.
    func testTheBodyCoversMostOfTheBox() {
        let loop = GlyphOutline.copilot[0]
        var area = 0.0
        for (index, point) in loop.enumerated() {
            let next = loop[(index + 1) % loop.count]
            area += Double(point.x * next.y - next.x * point.y)
        }
        XCTAssertGreaterThan(abs(area) / 2, 0.5, "the body covers less than half of its box")
    }
}

/// Canned answers for the quota endpoint, and the last request that reached
/// it, so the tests can say what left the app.
private final class CopilotStub: URLProtocol {
    struct Answer {
        let status: Int
        var body: Data = Data()
    }

    private static let lock = NSLock()
    private static var queued: [Answer] = []
    private static var served = 0
    private static var last: URLRequest?

    static func reset(_ answers: [Answer]) {
        lock.lock(); queued = answers; served = 0; last = nil; lock.unlock()
    }

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return served
    }

    static var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return last
    }

    static func session() -> URLSession {
        let configuration = ProviderHTTP.configuration()
        configuration.protocolClasses = [CopilotStub.self]
        return URLSession(configuration: configuration, delegate: ProviderHTTPDelegate(), delegateQueue: nil)
    }

    private static func next(for request: URLRequest) -> Answer {
        lock.lock(); defer { lock.unlock() }
        served += 1
        last = request
        return queued.isEmpty ? Answer(status: 500) : queued.removeFirst()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let answer = Self.next(for: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
