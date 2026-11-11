import XCTest
@testable import AINotch

@MainActor
final class UpdaterTests: XCTestCase {
    func testPreviewUpdaterDoesNotStartChecks() {
        let updater = Updater()
        XCTAssertFalse(updater.canCheckForUpdates)
        updater.checkForUpdates()
        XCTAssertFalse(updater.canCheckForUpdates)
    }

    func testShippedUpdateConfiguration() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let feed = try XCTUnwrap(URL(string: try XCTUnwrap(info["SUFeedURL"] as? String)))
        XCTAssertEqual(feed.scheme, "https")
        XCTAssertEqual(feed.host, "raw.githubusercontent.com")
        XCTAssertEqual(feed.path, "/s-chathuranga-j/AI-Notch/main/macos/updates/appcast.xml")
        let key = try XCTUnwrap(info["SUPublicEDKey"] as? String)
        XCTAssertEqual(Data(base64Encoded: key)?.count, 32)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info["SUAllowsAutomaticUpdates"] as? Bool, false)
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
    }
}
