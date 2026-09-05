import XCTest
@testable import 同频

final class AppIdentityTests: XCTestCase {
    func testApplicationUsesSameWaveIdentityAndKeepsChineseDisplayName() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.plus.samewave")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "同频")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "同频")
    }

    func testTestBundleUsesSameWaveIdentity() {
        let bundle = Bundle(for: AppIdentityTests.self)
        XCTAssertEqual(bundle.bundleIdentifier, "com.plus.samewave.tests")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, "SameWaveTests")
    }
}
