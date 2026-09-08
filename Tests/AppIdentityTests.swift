import AppKit
import XCTest
@testable import SameWave

final class AppIdentityTests: XCTestCase {
    @MainActor
    func testHostedTestsUseMemoryStorageAndDoNotRestorePersonalMeetings() throws {
        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let history = try XCTUnwrap(delegate.history)
        XCTAssertTrue(history.container.configurations.allSatisfy(\.isStoredInMemoryOnly))
        XCTAssertNil(delegate.coordinator.selectedRecordID)
    }

    func testApplicationUsesEnglishSameWaveIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.plus.samewave")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "SameWave")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "SameWave")
    }

    func testApplicationDeclaresEnglishAndSimplifiedChineseLocalizations() {
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String], ["en", "zh-Hans"])
        XCTAssertTrue(Set(["en", "zh-Hans"]).isSubset(of: Set(Bundle.main.localizations)))
    }

    func testTestBundleUsesSameWaveIdentity() {
        let bundle = Bundle(for: AppIdentityTests.self)
        XCTAssertEqual(bundle.bundleIdentifier, "com.plus.samewave.tests")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, "SameWaveTests")
    }
}
