import XCTest
import Sparkle
import AppKit
@testable import AINotch

@MainActor
final class UpdaterTests: XCTestCase {
    func testPreviewUpdaterDoesNotStartChecks() {
        let updater = Updater()
        XCTAssertFalse(updater.canCheckForUpdates)
        updater.checkForUpdates()
        XCTAssertFalse(updater.canCheckForUpdates)
    }

    func testUpdateWindowUsesSentencesWhenItBecomesKey() {
        let updater = Updater()
        let window = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("SUUpdateAlert")
        let label = NSTextField(labelWithString: "AI Notch 0.3.12 is now available—you have 0.3.11.")
        window.contentView?.addSubview(label)
        withExtendedLifetime(updater) {
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            XCTAssertEqual(label.stringValue, "AI Notch 0.3.12 is now available. You have 0.3.11.")
        }
        XCTAssertEqual(Updater.updateMessage("Ready to install"), "Ready to install")
    }

    func testSignedRunningAppCanCheckForUpdates() throws {
        let controller = SPUStandardUpdaterController(startingUpdater: false,
                                                      updaterDelegate: nil, userDriverDelegate: nil)
        try Updater().updater(controller.updater, mayPerform: .updates)
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
