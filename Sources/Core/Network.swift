import Foundation
import SystemConfiguration
import CoreWLAN
import Darwin

// MARK: - Bağlantı bilgisi (SCDynamicStore + getifaddrs, root yok)

public struct NetworkStatus: Sendable, Equatable {
    public let interface: String       // örn. en0
    public let isWiFi: Bool
    public let ipAddress: String?
    public let gateway: String?
    public let dnsServers: [String]
    public var isOnline: Bool { gateway != nil && ipAddress != nil }
}

public enum NetworkInfo {
    public static func current() -> NetworkStatus {
        let (iface, router) = globalIPv4()
        let dev = iface ?? "—"
        return NetworkStatus(
            interface: dev,
            isWiFi: dev.hasPrefix("en") && WiFiInfo.current() != nil,
            ipAddress: ipAddress(for: dev),
            gateway: router,
            dnsServers: globalDNS()
        )
    }

    static func globalIPv4() -> (interface: String?, router: String?) {
        guard let store = SCDynamicStoreCreate(nil, "PureGlass" as CFString, nil, nil),
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return (nil, nil) }
        return (dict["PrimaryInterface"] as? String, dict["Router"] as? String)
    }

    public static func globalDNS() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "PureGlass" as CFString, nil, nil),
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any]
        else { return [] }
        return dict["ServerAddresses"] as? [String] ?? []
    }

    static func ipAddress(for iface: String) -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let ifa = cur.pointee
            if String(cString: ifa.ifa_name) == iface,
               let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            ptr = ifa.ifa_next
        }
        return nil
    }
}

// MARK: - Wi-Fi (CoreWLAN, root yok)

public struct WiFiStatus: Sendable, Equatable {
    public let ssid: String?
    public let rssi: Int        // dBm (−30 mükemmel … −90 kötü)
    public let noise: Int
    public let txRate: Double   // Mbps (anlık link hızı)
    public let channel: Int

    /// RSSI → 0...1 sinyal kalitesi.
    public var quality: Double {
        let c = Swift.max(-100.0, Swift.min(-30.0, Double(rssi)))
        return (c + 100) / 70
    }
    public var bars: Int { Swift.max(0, Swift.min(4, Int((quality * 4).rounded(.up)))) }
}

public enum WiFiInfo {
    public static func current() -> WiFiStatus? {
        guard let i = CWWiFiClient.shared().interface() else { return nil }
        let rssi = i.rssiValue()
        guard rssi != 0 else { return nil }   // bağlı değil
        return WiFiStatus(ssid: i.ssid(), rssi: rssi, noise: i.noiseMeasurement(),
                          txRate: i.transmitRate(), channel: i.wlanChannel()?.channelNumber ?? 0)
    }
}

// MARK: - Kararlılık (ping) — bloklar, arka planda çağrılır

public enum PingMonitor {
    /// Tek ping; gecikme (ms) veya nil (kayıp/zaman aşımı).
    public static func ping(_ host: String, timeoutMs: Int = 1000) -> Double? {
        let p = Process()
        p.executableURL = URL(filePath: "/sbin/ping")
        p.arguments = ["-c", "1", "-W", "\(timeoutMs)", host]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let s = String(data: data, encoding: .utf8),
              let r = s.range(of: "time=") else { return nil }
        let num = s[r.upperBound...].prefix { $0.isNumber || $0 == "." }
        return Double(num)
    }
}

// MARK: - Hız testi (Apple networkQuality) — ~15-25 sn, arka planda

public struct SpeedResult: Sendable, Equatable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let responsiveness: Int   // RPM (yüksek = daha tepkisel)
}

// MARK: - DNS yönetimi (FAZ B) — okuma root yok; yazma AdminShell ile

public enum DNSManager {
    /// Arayüz (en0) → networksetup servis adı (Wi-Fi). networksetup IP komutları servis adı ister.
    public static func serviceName(for interface: String) -> String? {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/sbin/networksetup")
        p.arguments = ["-listnetworkserviceorder"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        let lines = s.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.contains("Device: \(interface))") && i > 0 {
            let name = lines[i - 1]
            if let r = name.range(of: ") ") {
                return String(name[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    public static func isValidIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { Int($0).map { $0 >= 0 && $0 <= 255 } ?? false }
    }

    /// `networksetup -setdnsservers` komutu. servers boş → "empty" (Otomatik/DHCP).
    /// Servis adı kabuk-tırnaklı, IP'ler doğrulanır → enjeksiyon güvenli. Geçersizse nil.
    public static func setDNSCommand(service: String, servers: [String]) -> String? {
        let svc = shellQuote(service)
        if servers.isEmpty {
            return "/usr/sbin/networksetup -setdnsservers \(svc) empty"
        }
        guard !servers.isEmpty, servers.allSatisfy(isValidIPv4) else { return nil }
        return "/usr/sbin/networksetup -setdnsservers \(svc) " + servers.joined(separator: " ")
    }

    /// DHCP kirasını yenile (IP yenile).
    public static func renewDHCPCommand(service: String) -> String {
        "/usr/sbin/networksetup -setdhcp \(shellQuote(service))"
    }

    public static let flushDNSCommand =
        "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum SpeedTest {
    public static func run() -> SpeedResult? {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/networkQuality")
        p.arguments = ["-c"]   // bitince JSON
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func d(_ k: String) -> Double {
            if let v = json[k] as? Double { return v }
            if let v = json[k] as? Int { return Double(v) }
            return 0
        }
        return SpeedResult(downloadMbps: d("dl_throughput") / 1_000_000,
                           uploadMbps: d("ul_throughput") / 1_000_000,
                           responsiveness: Int(d("responsiveness")))
    }
}
