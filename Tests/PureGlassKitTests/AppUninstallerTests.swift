import XCTest
@testable import PureGlassKit

final class AppUninstallerTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appending(path: "pgapp-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func makeApp(_ name: String, bundleID: String, in dir: URL) throws -> URL {
        let app = dir.appending(path: "\(name).app")
        let contents = app.appending(path: "Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(bundleID)</string>
        <key>CFBundleName</key><string>\(name)</string>
        </dict></plist>
        """
        try plist.write(to: contents.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
        fm.createFile(atPath: contents.appending(path: "blob.bin").path, contents: Data(repeating: 9, count: 5000))
        return app
    }

    func testFinderReadsBundleIDAndName() async throws {
        let appsDir = root.appending(path: "Applications")
        try fm.createDirectory(at: appsDir, withIntermediateDirectories: true)
        _ = try makeApp("TestApp", bundleID: "com.test.app", in: appsDir)

        let apps = await AppFinder().installedApps(in: [appsDir])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.name, "TestApp")
        XCTAssertEqual(apps.first?.bundleID, "com.test.app")
        XCTAssertFalse(apps.first!.isAppleApp)
        XCTAssertGreaterThan(apps.first!.size, 0)
    }

    func testFinderFlagsAppleApps() async throws {
        let appsDir = root.appending(path: "Applications")
        try fm.createDirectory(at: appsDir, withIntermediateDirectories: true)
        _ = try makeApp("Safari", bundleID: "com.apple.Safari", in: appsDir)
        let apps = await AppFinder().installedApps(in: [appsDir])
        XCTAssertTrue(apps.first!.isAppleApp)
    }

    func testLeftoverFinderMatchesByBundleID() throws {
        // Sahte ev dizini içinde artıklar oluştur.
        let home = root.appending(path: "home")
        let lib = home.appending(path: "Library")
        try fm.createDirectory(at: lib.appending(path: "Caches/com.test.app"), withIntermediateDirectories: true)
        fm.createFile(atPath: lib.appending(path: "Preferences/com.test.app.plist").path, contents: Data([1]))
        try fm.createDirectory(at: lib.appending(path: "Preferences"), withIntermediateDirectories: true)
        fm.createFile(atPath: lib.appending(path: "Preferences/com.test.app.plist").path, contents: Data([1]))
        try fm.createDirectory(at: lib.appending(path: "Application Support/TestApp"), withIntermediateDirectories: true)

        let app = InstalledApp(url: root.appending(path: "TestApp.app"), name: "TestApp",
                               bundleID: "com.test.app", size: 1, isAppleApp: false)
        let leftovers = AppLeftoverFinder(home: home).leftovers(for: app)
        let paths = leftovers.map { $0.url.lastPathComponent }
        XCTAssertTrue(paths.contains("com.test.app"), "Caches/com.test.app bulunmalı")
        XCTAssertTrue(paths.contains("com.test.app.plist"), "Preferences plist bulunmalı")
        XCTAssertTrue(paths.contains("TestApp"), "Application Support/TestApp bulunmalı")
    }

    func testLeftoverFinderIgnoresNonexistent() {
        let home = root.appending(path: "empty-home")
        let app = InstalledApp(url: root.appending(path: "X.app"), name: "Ghost",
                               bundleID: "com.ghost.none", size: 1, isAppleApp: false)
        XCTAssertTrue(AppLeftoverFinder(home: home).leftovers(for: app).isEmpty)
    }
}
