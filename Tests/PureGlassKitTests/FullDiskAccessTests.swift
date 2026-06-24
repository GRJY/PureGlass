import XCTest
@testable import PureGlassKit

final class FullDiskAccessTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appending(path: "pgfda-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // chmod'u geri al ki silinebilsin
        let locked = dir.appending(path: "locked")
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
        try? fm.removeItem(at: dir)
    }

    func testGrantedWhenProbeReadable() {
        let readable = dir.appending(path: "ok.db")
        fm.createFile(atPath: readable.path, contents: Data([0x1]))
        let fda = FullDiskAccess(probePaths: [readable])
        XCTAssertEqual(fda.currentStatus(), .granted)
    }

    func testDeniedWhenProbeExistsButUnreadable() throws {
        let locked = dir.appending(path: "locked")
        fm.createFile(atPath: locked.path, contents: Data([0x1]))
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let fda = FullDiskAccess(probePaths: [locked])
        XCTAssertEqual(fda.currentStatus(), .denied)
    }

    func testUnknownWhenNoProbeExists() {
        let ghost = dir.appending(path: "nope.db")
        let fda = FullDiskAccess(probePaths: [ghost])
        XCTAssertEqual(fda.currentStatus(), .unknown)
    }

    func testFallsThroughToReadableProbe() {
        let ghost = dir.appending(path: "nope.db")
        let readable = dir.appending(path: "ok.db")
        fm.createFile(atPath: readable.path, contents: Data([0x1]))
        let fda = FullDiskAccess(probePaths: [ghost, readable])
        XCTAssertEqual(fda.currentStatus(), .granted)
    }

    func testSettingsURLIsValid() {
        XCTAssertEqual(FullDiskAccess.settingsURL.scheme, "x-apple.systempreferences")
    }

    @MainActor
    func testCoordinatorReflectsInitialStatus() {
        let readable = dir.appending(path: "ok.db")
        fm.createFile(atPath: readable.path, contents: Data([0x1]))
        let coord = PermissionCoordinator(fda: FullDiskAccess(probePaths: [readable]))
        XCTAssertEqual(coord.status, .granted)
        XCTAssertTrue(coord.isGranted)
    }
}
