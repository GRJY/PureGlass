import XCTest
@testable import PureGlassKit

final class PureGlassKitInfoTests: XCTestCase {
    func testVersionIsNotEmpty() {
        XCTAssertFalse(PureGlassKitInfo.version.isEmpty)
    }

    func testModuleName() {
        XCTAssertEqual(PureGlassKitInfo.name, "PureGlassKit")
    }
}
