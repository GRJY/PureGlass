import XCTest
@testable import PureGlassKit

final class NetworkInfoTests: XCTestCase {
    func testCurrentStatusPlausible() throws {
        let s = NetworkInfo.current()
        guard s.gateway != nil else { throw XCTSkip("Aktif ağ yok (ör. CI)") }
        XCTAssertNotEqual(s.interface, "—")
        XCTAssertNotNil(s.ipAddress)
        XCTAssertTrue(s.isOnline)
    }

    func testPingReachable() throws {
        guard let ms = PingMonitor.ping("1.1.1.1", timeoutMs: 2000) else {
            throw XCTSkip("İnternet yok / ping engelli")
        }
        XCTAssertGreaterThan(ms, 0)
        XCTAssertLessThan(ms, 5000)
    }

    func testWiFiOrSkip() throws {
        guard let w = WiFiInfo.current() else { throw XCTSkip("Wi-Fi bağlı değil") }
        XCTAssertTrue((-100...0).contains(w.rssi))
        XCTAssertTrue((0...1).contains(w.quality))
        XCTAssertTrue((0...4).contains(w.bars))
    }
}

final class DNSManagerTests: XCTestCase {
    func testIPv4Validation() {
        XCTAssertTrue(DNSManager.isValidIPv4("1.1.1.1"))
        XCTAssertTrue(DNSManager.isValidIPv4("192.168.0.1"))
        XCTAssertFalse(DNSManager.isValidIPv4("999.1.1.1"))
        XCTAssertFalse(DNSManager.isValidIPv4("1.1.1"))
        XCTAssertFalse(DNSManager.isValidIPv4("a.b.c.d"))
        XCTAssertFalse(DNSManager.isValidIPv4("1.1.1.1; rm -rf /"))
    }

    func testSetDNSCommandValid() {
        let cmd = DNSManager.setDNSCommand(service: "Wi-Fi", servers: ["1.1.1.1", "1.0.0.1"])
        XCTAssertEqual(cmd, "/usr/sbin/networksetup -setdnsservers 'Wi-Fi' 1.1.1.1 1.0.0.1")
    }

    func testSetDNSAutoIsEmpty() {
        let cmd = DNSManager.setDNSCommand(service: "Wi-Fi", servers: [])
        XCTAssertEqual(cmd, "/usr/sbin/networksetup -setdnsservers 'Wi-Fi' empty")
    }

    func testSetDNSRejectsInjection() {
        // Geçersiz IP → komut üretilmez (enjeksiyon engellenir).
        XCTAssertNil(DNSManager.setDNSCommand(service: "Wi-Fi", servers: ["1.1.1.1; rm -rf /"]))
        // Servis adındaki tırnak kaçışlanır.
        let cmd = DNSManager.setDNSCommand(service: "My'Net", servers: [])
        XCTAssertEqual(cmd, "/usr/sbin/networksetup -setdnsservers 'My'\\''Net' empty")
    }
}
