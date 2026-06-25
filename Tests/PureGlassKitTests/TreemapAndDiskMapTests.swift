import XCTest
import CoreGraphics
@testable import PureGlassKit

final class TreemapLayoutTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 200, height: 100)

    func testReturnsSameCount() {
        let frames = squarifiedTreemap(weights: [5, 3, 2], in: rect)
        XCTAssertEqual(frames.count, 3)
    }

    func testEmptyWeightsGivesZeroRects() {
        XCTAssertTrue(squarifiedTreemap(weights: [], in: rect).isEmpty)
        let zeros = squarifiedTreemap(weights: [0, 0], in: rect)
        XCTAssertEqual(zeros, [.zero, .zero])
    }

    func testAllFramesWithinBounds() {
        let frames = squarifiedTreemap(weights: [10, 6, 4, 3, 2, 1], in: rect)
        for f in frames {
            XCTAssertGreaterThanOrEqual(f.minX, -0.01)
            XCTAssertGreaterThanOrEqual(f.minY, -0.01)
            XCTAssertLessThanOrEqual(f.maxX, rect.width + 0.01)
            XCTAssertLessThanOrEqual(f.maxY, rect.height + 0.01)
        }
    }

    func testTotalAreaApproximatesRect() {
        let frames = squarifiedTreemap(weights: [10, 6, 4, 3, 2, 1], in: rect)
        let area = frames.reduce(0.0) { $0 + Double($1.width * $1.height) }
        XCTAssertEqual(area, Double(rect.width * rect.height), accuracy: 1.0)
    }

    func testAreaProportionalToWeight() {
        let weights = [6.0, 3.0, 1.0]
        let frames = squarifiedTreemap(weights: weights, in: rect)
        let totalWeight = weights.reduce(0, +)
        let rectArea = Double(rect.width * rect.height)
        for (i, f) in frames.enumerated() {
            let expected = rectArea * weights[i] / totalWeight
            XCTAssertEqual(Double(f.width * f.height), expected, accuracy: rectArea * 0.02)
        }
    }
}

final class DiskMapScannerTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appending(path: "pgmap-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func write(_ rel: String, _ bytes: Int) throws {
        let url = root.appending(path: rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data(repeating: 7, count: bytes))
    }

    func testChildrenSizesAndSorting() async throws {
        try write("big/a.bin", 100_000)
        try write("big/b.bin", 100_000)
        try write("small.bin", 1_000)

        let children = await DiskMapScanner().children(of: root)
        XCTAssertEqual(children.count, 2)                    // "big" dizini + "small.bin"
        XCTAssertEqual(children.first?.name, "big")          // en büyük önce
        XCTAssertTrue(children.first!.isDirectory)
        XCTAssertEqual(children.first?.fileCount, 2)
        XCTAssertGreaterThan(children.first!.size, children.last!.size)
    }

    func testSkipsSymlinks() async throws {
        try write("real.bin", 1_000)
        let outside = fm.temporaryDirectory.appending(path: "pgmap-out-\(UUID().uuidString)")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }
        try fm.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: outside)

        let children = await DiskMapScanner().children(of: root)
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children.first?.name, "real.bin")
    }
}
