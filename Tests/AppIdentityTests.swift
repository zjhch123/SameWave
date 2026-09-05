import XCTest
@testable import SameWave

final class AppIdentityTests: XCTestCase {
    func testApplicationUsesEnglishSameWaveIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.plus.samewave")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "SameWave")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "SameWave")
    }

    func testApplicationDeclaresEnglishLocalization() {
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String], ["en"])
    }

    func testTestBundleUsesSameWaveIdentity() {
        let bundle = Bundle(for: AppIdentityTests.self)
        XCTAssertEqual(bundle.bundleIdentifier, "com.plus.samewave.tests")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, "SameWaveTests")
    }
}
