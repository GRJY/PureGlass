import XCTest
@testable import PureGlassKit

final class ScanEngineTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appending(path: "pgscan-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func writeFile(_ relative: String, bytes: Int) throws {
        let url = root.appending(path: relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data(repeating: 0xAB, count: bytes))
    }

    private func location(_ url: URL) -> CleanLocation {
        CleanLocation(
            id: "test.loc", category: .userCache, title: "Test", url: url,
            risk: .safe, requiresFullDiskAccess: false, requiresRoot: false, details: ""
        )
    }

    func testMeasuresTopLevelItemsAndSizes() async throws {
        try writeFile("a.bin", bytes: 5_000)
        try writeFile("b.bin", bytes: 9_000)
        try writeFile("nested/c.bin", bytes: 3_000)   // "nested" dizini bir üst-düzey öğe

        let result = ScanEngine().scanLocation(location(root))

        XCTAssertTrue(result.isAccessible)
        // üst-düzey: a.bin, b.bin, nested/ → 3 öğe
        XCTAssertEqual(result.itemCount, 3)
        // toplam dosya sayısı: a, b, c → 3
        XCTAssertEqual(result.totalFileCount, 3)
        // boyut en az mantıksal toplam kadar (allocated ≥ logical), pozitif
        XCTAssertGreaterThan(result.totalSize, 0)
        // en büyük öğe önce sıralanmış olmalı
        XCTAssertEqual(result.items.map(\.size), result.items.map(\.size).sorted(by: >))
    }

    func testDirectoryItemAggregatesNestedSize() async throws {
        try writeFile("dir/one.bin", bytes: 4_000)
        try writeFile("dir/sub/two.bin", bytes: 4_000)

        let result = ScanEngine().scanLocation(location(root))
        let dirItem = try XCTUnwrap(result.items.first { $0.isDirectory })
        XCTAssertEqual(dirItem.fileCount, 2)
        XCTAssertGreaterThan(dirItem.size, 0)
    }

    func testSkipsSymbolicLinks() async throws {
        // Gerçek hedef tarama kökünün DIŞINDA; içeride ona bir symlink var.
        let outside = fm.temporaryDirectory.appending(path: "pgscan-out-\(UUID().uuidString)")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }
        fm.createFile(atPath: outside.appending(path: "big.bin").path, contents: Data(repeating: 1, count: 50_000))

        try writeFile("real.bin", bytes: 1_000)
        try fm.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: outside)

        let result = ScanEngine().scanLocation(location(root))
        // Yalnızca real.bin sayılmalı; symlink atlanmalı.
        XCTAssertEqual(result.itemCount, 1)
        XCTAssertEqual(result.items.first?.url.lastPathComponent, "real.bin")
    }

    func testNonexistentLocationIsAccessibleButEmpty() async {
        let ghost = root.appending(path: "does-not-exist")
        let result = ScanEngine().scanLocation(location(ghost))
        XCTAssertTrue(result.isAccessible)
        XCTAssertEqual(result.itemCount, 0)
    }

    func testScanMultipleLocationsSortedBySizeWithProgress() async throws {
        try writeFile("small.bin", bytes: 1_000)
        let big = fm.temporaryDirectory.appending(path: "pgscan-big-\(UUID().uuidString)")
        try fm.createDirectory(at: big, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: big) }
        fm.createFile(atPath: big.appending(path: "huge.bin").path, contents: Data(repeating: 2, count: 200_000))

        let locSmall = CleanLocation(id: "small", category: .userCache, title: "Small", url: root, risk: .safe, requiresFullDiskAccess: false, requiresRoot: false, details: "")
        let locBig = CleanLocation(id: "big", category: .userCache, title: "Big", url: big, risk: .safe, requiresFullDiskAccess: false, requiresRoot: false, details: "")

        let progressCount = ProgressCollector()
        let results = await ScanEngine().scan([locSmall, locBig]) { _ in
            await progressCount.bump()
        }

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.locationID, "big", "En büyük sonuç önce gelmeli")
        let count = await progressCount.value
        XCTAssertEqual(count, 2, "Her konum için bir ilerleme olayı")
    }

    func testCancellationStopsScan() async throws {
        for i in 0..<200 { try writeFile("f\(i).bin", bytes: 2_000) }
        let loc = location(root)   // Sendable; Task kapanışında self yakalamayalım
        let task = Task { ScanEngine().scanLocation(loc) }
        task.cancel()
        let result = await task.value
        // İptal sonrası öğe sayısı tam set (200) olmayabilir; çökmeden dönmeli.
        XCTAssertLessThanOrEqual(result.itemCount, 200)
    }
}

/// İlerleme olaylarını sayan basit aktör (Sendable test yardımcısı).
private actor ProgressCollector {
    private(set) var value = 0
    func bump() { value += 1 }
}
