import XCTest
@testable import PureGlassKit

final class SafetyGuardTests: XCTestCase {
    private var tmpRoot: URL!
    private var outsideRoot: URL!
    private var guardian: SafetyGuard!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        // İzinli kök olarak geçici bir dizin; ev dizininden bağımsız test.
        tmpRoot = fm.temporaryDirectory.appending(path: "pgtest-allowed-\(UUID().uuidString)")
        outsideRoot = fm.temporaryDirectory.appending(path: "pgtest-outside-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        guardian = SafetyGuard(allowedRoots: [tmpRoot])
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmpRoot)
        try? fm.removeItem(at: outsideRoot)
    }

    // MARK: - Geçerli durumlar

    func testAcceptsChildOfAllowedRoot() throws {
        let child = tmpRoot.appending(path: "SomeApp/Cache/blob.bin")
        try fm.createDirectory(at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: child.path, contents: Data([0x1]))
        XCTAssertNoThrow(try guardian.validate(child))
        XCTAssertTrue(guardian.isValid(child))
    }

    func testAcceptsNonExistentChild() {
        // Henüz var olmayan ama izinli kök altındaki yol da yapısal olarak geçerli olmalı.
        let child = tmpRoot.appending(path: "ghost/file")
        XCTAssertNoThrow(try guardian.validate(child))
    }

    // MARK: - Reddedilmesi gerekenler

    func testRejectsRoot() {
        XCTAssertThrowsError(try guardian.validate(URL(filePath: "/")))
    }

    func testRejectsSystem() {
        XCTAssertThrowsError(try guardian.validate(URL(filePath: "/System/Library/Caches/x"))) { error in
            XCTAssertEqual(error as? SafetyGuard.Violation, .protectedSystemPath("/System/Library/Caches/x"))
        }
    }

    func testRejectsUsr() {
        XCTAssertThrowsError(try guardian.validate(URL(filePath: "/usr/lib/whatever")))
    }

    func testRejectsApplications() {
        XCTAssertThrowsError(try guardian.validate(URL(filePath: "/Applications/Safari.app")))
    }

    func testRejectsAllowedRootItself() {
        XCTAssertThrowsError(try guardian.validate(tmpRoot)) { error in
            guard case .allowedRootItself = error as? SafetyGuard.Violation else {
                return XCTFail("allowedRootItself bekleniyordu, gelen: \(error)")
            }
        }
    }

    func testRejectsOutsideAllowedRoots() {
        let outsideChild = outsideRoot.appending(path: "file.txt")
        XCTAssertThrowsError(try guardian.validate(outsideChild)) { error in
            guard case .outsideAllowedRoots = error as? SafetyGuard.Violation else {
                return XCTFail("outsideAllowedRoots bekleniyordu, gelen: \(error)")
            }
        }
    }

    func testRejectsHomeDirectory() {
        let home = fm.homeDirectoryForCurrentUser
        XCTAssertThrowsError(try guardian.validate(home))
        XCTAssertThrowsError(try guardian.validate(home.appending(path: "Documents")))
    }

    // MARK: - Sembolik link kaçışı (TOCTOU koruması)

    func testRejectsSymlinkEscape() throws {
        // İzinli kök içindeki bir symlink, izinli alan DIŞINI gösteriyor.
        let escapeTarget = outsideRoot.appending(path: "secret.txt")
        fm.createFile(atPath: escapeTarget.path, contents: Data([0x2]))
        let link = tmpRoot.appending(path: "evil-link")
        try fm.createSymbolicLink(at: link, withDestinationURL: escapeTarget)

        XCTAssertThrowsError(try guardian.validate(link)) { error in
            guard case .symlinkEscape = error as? SafetyGuard.Violation else {
                return XCTFail("symlinkEscape bekleniyordu, gelen: \(error)")
            }
        }
    }

    func testRejectsSymlinkToSystem() throws {
        // İzinli kök içindeki symlink /System'i gösteriyor → korumalı olarak yakalanır.
        let link = tmpRoot.appending(path: "sys-link")
        try fm.createSymbolicLink(at: link, withDestinationURL: URL(filePath: "/System/Library"))
        XCTAssertThrowsError(try guardian.validate(link))
    }

    // MARK: - Veritabanından üretim

    func testGuardFromDatabaseProtectsSystemButAllowsCacheChild() {
        let db = LocationsDatabase()
        let g = SafetyGuard(database: db)
        // Korumalı yol reddedilir
        XCTAssertThrowsError(try g.validate(URL(filePath: "/System/Library/x")))
        // ~/Library/Caches altındaki bir çocuk kabul edilir
        let cacheChild = db.locations.first { $0.id == "user.cache" }!.url.appending(path: "demo/file")
        XCTAssertNoThrow(try g.validate(cacheChild))
    }
}
