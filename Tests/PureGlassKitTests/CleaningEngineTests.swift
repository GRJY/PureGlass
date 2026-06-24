import XCTest
@testable import PureGlassKit

final class CleaningEngineTests: XCTestCase {
    private var root: URL!
    private var outside: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appending(path: "pgclean-\(UUID().uuidString)")
        outside = fm.temporaryDirectory.appending(path: "pgclean-out-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
        try? fm.removeItem(at: outside)
    }

    private func makeFile(_ dir: URL, _ name: String, bytes: Int = 100) -> URL {
        let url = dir.appending(path: name)
        fm.createFile(atPath: url.path, contents: Data(repeating: 0xCD, count: bytes))
        return url
    }

    private func item(_ url: URL, size: Int64 = 100) -> FileItem {
        FileItem(url: url, size: size, isDirectory: false, fileCount: 1,
                 modificationDate: nil, category: .userCache, risk: .safe)
    }

    /// Gerçek Çöp'ü kirletmemek için: enjekte edilmiş "trash" = gerçekten sil + kaydet.
    private func recordingEngine() -> (CleaningEngine, TrashRecorder) {
        let recorder = TrashRecorder()
        let engine = CleaningEngine(safety: SafetyGuard(allowedRoots: [root])) { url in
            recorder.add(url)
            try FileManager.default.removeItem(at: url)
        }
        return (engine, recorder)
    }

    func testTrashesValidItems() async {
        let a = makeFile(root, "a.bin")
        let b = makeFile(root, "b.bin")
        let (engine, recorder) = recordingEngine()

        let report = await engine.clean([item(a), item(b)])

        XCTAssertEqual(report.trashedCount, 2)
        XCTAssertEqual(report.failedCount, 0)
        XCTAssertEqual(report.skippedCount, 0)
        XCTAssertEqual(report.bytesReclaimed, 200)
        XCTAssertFalse(fm.fileExists(atPath: a.path))
        XCTAssertFalse(fm.fileExists(atPath: b.path))
        XCTAssertEqual(recorder.count, 2)
    }

    func testSkipsUnsafePathOutsideAllowedRoots() async {
        let danger = makeFile(outside, "important.txt")   // izinli kök DIŞINDA
        let (engine, recorder) = recordingEngine()

        let report = await engine.clean([item(danger)])

        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertEqual(report.trashedCount, 0)
        if case .skippedUnsafe = report.events.first?.outcome {} else {
            XCTFail("skippedUnsafe bekleniyordu")
        }
        XCTAssertTrue(fm.fileExists(atPath: danger.path), "Güvensiz dosya ASLA silinmemeli")
        XCTAssertEqual(recorder.count, 0, "Trash işlemi hiç çağrılmamalı")
    }

    func testFailsGracefullyOnNonexistentItem() async {
        let ghost = root.appending(path: "ghost.bin")   // izinli kök içinde ama yok
        let (engine, _) = recordingEngine()

        let report = await engine.clean([item(ghost)])

        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.trashedCount, 0)
    }

    func testMixedBatchContinuesAfterFailure() async {
        let good = makeFile(root, "good.bin")
        let unsafe = makeFile(outside, "unsafe.bin")
        let ghost = root.appending(path: "ghost.bin")
        let (engine, _) = recordingEngine()

        let report = await engine.clean([item(unsafe), item(ghost), item(good)])

        XCTAssertEqual(report.trashedCount, 1)
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.events.count, 3, "Her öğe için bir olay, hata sonrası da devam")
    }

    func testEmitsLiveEventPerItem() async {
        let a = makeFile(root, "a.bin")
        let b = makeFile(root, "b.bin")
        let (engine, _) = recordingEngine()
        let collector = EventCollector()

        _ = await engine.clean([item(a), item(b)]) { event in
            await collector.add(event)
        }

        let count = await collector.count
        XCTAssertEqual(count, 2)
    }

    func testNeverTrashesSystemPath() async {
        let (engine, recorder) = recordingEngine()
        let report = await engine.clean([item(URL(filePath: "/System/Library/Caches/x"))])
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertEqual(recorder.count, 0)
    }
}

/// Thread-safe çağrı sayacı (enjekte edilen trash kapanışı @Sendable).
private final class TrashRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return urls.count }
}

private actor EventCollector {
    private(set) var count = 0
    func add(_ event: CleanEvent) { count += 1 }
}
