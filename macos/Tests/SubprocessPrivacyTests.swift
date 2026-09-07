import XCTest
@testable import AINotch

final class SubprocessPrivacyTests: XCTestCase {
    func testCancellationBeforeLaunchPreventsProcessExecution() {
        let cancellation = CodexBridge.ProcessCancellation()
        cancellation.cancel()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        XCTAssertThrowsError(try cancellation.run(process))
        XCTAssertFalse(process.isRunning)
    }

    func testCancellationStopsAnAlreadyRunningProcess() throws {
        let cancellation = CodexBridge.ProcessCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["2"]
        try cancellation.run(process)
        cancellation.cancel()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
    }
}
