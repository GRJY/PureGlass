import XCTest
@testable import PureGlassKit

final class DuplicateFinderTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appending(path: "pgdup-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func write(_ rel: String, _ content: String) throws {
        let url = dir.appending(path: rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.data(using: .utf8)!.write(to: url)
    }

    func testFindsIdenticalContent() async throws {
        let dup = String(repeating: "AB", count: 5000)   // > minSize
        try write("a.bin", dup)
        try write("sub/b.bin", dup)        // farklı isim/konum, aynı içerik
        try write("c.bin", String(repeating: "ZZ", count: 5000))  // farklı içerik

        let groups = await DuplicateFinder().find(in: [dir])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.urls.count, 2)
        XCTAssertGreaterThan(groups.first!.wastedBytes, 0)
    }

    func testNoDuplicatesWhenUnique() async throws {
        try write("a.bin", String(repeating: "1", count: 5000))
        try write("b.bin", String(repeating: "2", count: 5000))
        let groups = await DuplicateFinder().find(in: [dir])
        XCTAssertTrue(groups.isEmpty)
    }

    func testIgnoresSmallFiles() async throws {
        try write("a.txt", "hi")   // < minSize
        try write("b.txt", "hi")
        let groups = await DuplicateFinder().find(in: [dir], minSize: 4096)
        XCTAssertTrue(groups.isEmpty)
    }

    func testSameSizeDifferentContentNotGrouped() async throws {
        try write("a.bin", String(repeating: "A", count: 6000))
        try write("b.bin", String(repeating: "B", count: 6000))  // aynı boyut, farklı içerik
        let groups = await DuplicateFinder().find(in: [dir])
        XCTAssertTrue(groups.isEmpty)
    }

    func testWastedBytesAccounting() async throws {
        let dup = String(repeating: "Q", count: 8000)
        try write("a.bin", dup); try write("b.bin", dup); try write("c.bin", dup)
        let groups = await DuplicateFinder().find(in: [dir])
        XCTAssertEqual(groups.first?.urls.count, 3)
        // 3 kopya → 2 silinebilir → wasted = 2 * size
        XCTAssertEqual(groups.first?.wastedBytes, groups.first!.size * 2)
    }
}
