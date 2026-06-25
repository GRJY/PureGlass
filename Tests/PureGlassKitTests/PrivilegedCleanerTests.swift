import XCTest
@testable import PureGlassKit

final class PrivilegedCleanerTests: XCTestCase {
    private var root: URL!
    private var outside: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appending(path: "pgpriv-\(UUID().uuidString)")
        outside = fm.temporaryDirectory.appending(path: "pgpriv-out-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
        try? fm.removeItem(at: outside)
    }

    private func make(_ dir: URL, _ name: String) -> URL {
        let url = dir.appending(path: name)
        fm.createFile(atPath: url.path, contents: Data([0x1]))
        return url
    }

    private func item(_ url: URL) -> FileItem {
        FileItem(url: url, size: 1, isDirectory: false, fileCount: 1,
                 modificationDate: nil, category: .systemCache, risk: .caution, requiresRoot: true)
    }

    /// Komutu gerçekten (root olmadan) çalıştır → doğruluk + kaçış kanıtı.
    @discardableResult
    private func runShell(_ command: String) -> Int32 {
        let p = Process()
        p.executableURL = URL(filePath: "/bin/sh")
        p.arguments = ["-c", command]
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    func testPartitionAllowsSystemRootChildrenRejectsOutside() {
        let cleaner = PrivilegedCleaner(safety: SafetyGuard(allowedRoots: [root]))
        let good = item(make(root, "a.cache"))
        let bad = item(make(outside, "important"))
        let (valid, skipped) = cleaner.partition([good, bad])
        XCTAssertEqual(valid.map(\.url), [good.url])
        XCTAssertEqual(skipped.map(\.url), [bad.url])
    }

    func testBuildCommandIsNilForEmpty() {
        let cleaner = PrivilegedCleaner(safety: SafetyGuard(allowedRoots: [root]))
        XCTAssertNil(cleaner.buildCommand(for: []))
    }

    func testBuiltCommandActuallyDeletesValidFiles() {
        let cleaner = PrivilegedCleaner(safety: SafetyGuard(allowedRoots: [root]))
        let a = make(root, "a.cache")
        let b = make(root, "b.cache")
        let cmd = cleaner.buildCommand(for: [a, b])!
        XCTAssertEqual(runShell(cmd), 0)
        XCTAssertFalse(fm.fileExists(atPath: a.path))
        XCTAssertFalse(fm.fileExists(atPath: b.path))
    }

    func testInjectionSafetyWithQuotesAndSpacesInPath() {
        let cleaner = PrivilegedCleaner(safety: SafetyGuard(allowedRoots: [root]))
        // Tehlikeli karakterler içeren ad: tek tırnak, boşluk, noktalı virgül.
        let tricky = make(root, "we'ird ; name.cache")
        // Yanında DOKUNULMAMASI gereken bir tanık dosya.
        let witness = make(root, "witness.cache")
        let cmd = cleaner.buildCommand(for: [tricky])!
        XCTAssertEqual(runShell(cmd), 0)
        XCTAssertFalse(fm.fileExists(atPath: tricky.path), "Tırnaklı dosya silinmeli")
        XCTAssertTrue(fm.fileExists(atPath: witness.path), "Enjeksiyon tanık dosyaya zarar vermemeli")
    }

    func testCleanerFromDatabaseOnlyAllowsSystemRoots() {
        let db = LocationsDatabase()
        let cleaner = PrivilegedCleaner(database: db)
        // Kullanıcı cache'i (root değil) → privileged cleaner REDDETMELİ
        let userCache = db.locations.first { $0.id == "user.cache" }!.url.appending(path: "x")
        XCTAssertFalse(cleaner.safety.isValid(userCache))
        // Sistem cache child → kabul
        let sysCache = db.locations.first { $0.id == "system.cache" }!.url.appending(path: "x")
        XCTAssertTrue(cleaner.safety.isValid(sysCache))
        // /System asla
        XCTAssertFalse(cleaner.safety.isValid(URL(filePath: "/System/Library/x")))
    }
}
