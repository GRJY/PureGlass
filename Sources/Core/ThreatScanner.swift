import Foundation

/// Tespit edilen bir tehdit/şüpheli öğe.
public struct Threat: Identifiable, Sendable, Hashable {
    public enum Severity: Int, Sendable, Comparable {
        case info, suspicious, malicious
        public static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
        public var title: String {
            switch self {
            case .info: return "Bilgi"
            case .suspicious: return "Şüpheli"
            case .malicious: return "Zararlı"
            }
        }
    }

    public enum Category: String, Sendable {
        case launchItem      // LaunchAgent/Daemon kalıcılığı
        case knownMalware    // bilinen adware/malware göstergesi
        case hostsHijack     // /etc/hosts ele geçirme
    }

    public let id: String
    public let title: String
    public let detail: String
    public let path: URL?
    public let severity: Severity
    public let category: Category

    public init(id: String, title: String, detail: String, path: URL?, severity: Severity, category: Category) {
        self.id = id
        self.title = title
        self.detail = detail
        self.path = path
        self.severity = severity
        self.category = category
    }
}

/// Sezgisel + bilinen-gösterge tabanlı tehdit tarayıcı (offline, gizlilik dostu).
/// Tam antivirüs DEĞİLDİR; bulut imza veritabanı kullanmaz.
public struct ThreatScanner: Sendable {
    let launchDirs: [URL]
    let hostsFile: URL
    let knownAppPaths: [URL]

    /// Belgelenmiş macOS adware/malware aileleri (etiket/yol parçaları).
    static let knownIndicators: [String] = [
        "genieo", "pirrit", "bundlore", "adload", "vsearch", "spigot", "crossrider",
        "conduit", "installmac", "searchmine", "trovi", "mughthesec", "shlayer",
        "mackeeper", "cpuminer", "xmrig", "keranger", "silversparrow", "geneio",
        "macsearch", "advancedmaccleaner", "pcvark", "amccleaner"
    ]

    /// Yalnızca loopback olmayan IP'ye yönlendirilirse ele geçirme sayılan hassas alan adları.
    static let sensitiveDomains: [String] = [
        "apple.com", "icloud.com", "mzstatic.com", "malwarebytes", "norton",
        "mcafee", "kaspersky", "virustotal", "objective-see"
    ]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        launchDirs: [URL]? = nil,
        hostsFile: URL = URL(filePath: "/etc/hosts"),
        knownAppPaths: [URL]? = nil
    ) {
        self.launchDirs = launchDirs ?? [
            home.appending(path: "Library/LaunchAgents"),
            URL(filePath: "/Library/LaunchAgents"),
            URL(filePath: "/Library/LaunchDaemons")
        ]
        self.hostsFile = hostsFile
        self.knownAppPaths = knownAppPaths ?? [
            URL(filePath: "/Applications/MacKeeper.app"),
            URL(filePath: "/Applications/Advanced Mac Cleaner.app"),
            URL(filePath: "/Applications/MacBooster.app"),
            home.appending(path: "Library/Application Support/MacKeeper")
        ]
    }

    public func scan() async -> [Threat] {
        var threats: [Threat] = []
        let fm = FileManager.default

        // 1) Launch agent/daemon plist'leri
        for dir in launchDirs {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for url in entries where url.pathExtension == "plist" {
                if Task.isCancelled { break }
                if let t = inspectLaunchPlist(url) { threats.append(t) }
            }
        }

        // 2) Bilinen PUP/malware uygulama yolları
        for url in knownAppPaths where fm.fileExists(atPath: url.path) {
            threats.append(Threat(
                id: "known:\(url.path)",
                title: "Bilinen istenmeyen yazılım: \(url.lastPathComponent)",
                detail: "Yaygın olarak adware/PUP kategorisinde bilinen bir yazılım.",
                path: url, severity: .malicious, category: .knownMalware))
        }

        // 3) hosts dosyası ele geçirme
        if let contents = try? String(contentsOf: hostsFile, encoding: .utf8) {
            threats += inspectHosts(contents)
        }

        return threats.sorted { $0.severity > $1.severity }
    }

    // MARK: - Test edilebilir parçalar

    func inspectLaunchPlist(_ url: URL) -> Threat? {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        let label = (dict["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let args: [String]
        if let pa = dict["ProgramArguments"] as? [String] { args = pa }
        else if let p = dict["Program"] as? String { args = [p] }
        else { args = [] }
        let joined = args.joined(separator: " ").lowercased()
        let lowerLabel = label.lowercased()

        // a) Bilinen gösterge (etiket/komut)
        for sig in Self.knownIndicators where lowerLabel.contains(sig) || joined.contains(sig) {
            return Threat(id: "launch:\(url.path)", title: "Bilinen zararlı/adware: \(label)",
                          detail: "Bilinen tehdit göstergesi '\(sig)' içeriyor.\nYol: \(url.lastPathComponent)",
                          path: url, severity: .malicious, category: .knownMalware)
        }

        // b) İnternetten indirip çalıştıran kalıcı görev (klasik dropper)
        let downloads = joined.contains("curl") || joined.contains("wget")
        let pipesToShell = joined.contains("sh") || joined.contains("bash") || joined.contains("| sh")
        if downloads && pipesToShell {
            return Threat(id: "launch:\(url.path)", title: "İnternetten indirip çalıştıran görev",
                          detail: "Kalıcı görev internetten içerik indirip çalıştırıyor (dropper davranışı).\n\(joined)",
                          path: url, severity: .malicious, category: .launchItem)
        }

        // c) Gizleme/obfuscation göstergeleri
        let badPatterns = ["base64", "osascript -e", "python -c", "eval ", "/tmp/", "/private/tmp/", "/users/shared/", "/var/tmp/"]
        if let hit = badPatterns.first(where: { joined.contains($0) }) {
            return Threat(id: "launch:\(url.path)", title: "Şüpheli kalıcı görev: \(label)",
                          detail: "Şüpheli desen '\(hit.trimmingCharacters(in: .whitespaces))' içeriyor.",
                          path: url, severity: .suspicious, category: .launchItem)
        }

        // d) Kullanıcı LaunchAgents'ında Apple taklidi
        let isUserAgent = url.path.contains("/Library/LaunchAgents") && url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path)
        if isUserAgent, lowerLabel.hasPrefix("com.apple."), let prog = args.first,
           !prog.hasPrefix("/System/"), !prog.hasPrefix("/usr/"), !prog.hasPrefix("/Library/Apple") {
            return Threat(id: "launch:\(url.path)", title: "Apple taklidi şüpheli görev: \(label)",
                          detail: "Kullanıcı klasöründe 'com.apple.' etiketli ama Apple yolunda olmayan görev.",
                          path: url, severity: .suspicious, category: .launchItem)
        }

        return nil
    }

    func inspectHosts(_ contents: String) -> [Threat] {
        var threats: [Threat] = []
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let ip = parts[0]
            let isLoopback = ip == "127.0.0.1" || ip == "::1" || ip == "0.0.0.0"
            guard !isLoopback else { continue }
            for domain in parts.dropFirst() {
                let d = domain.lowercased()
                if Self.sensitiveDomains.contains(where: { d.contains($0) }) {
                    threats.append(Threat(
                        id: "hosts:\(d)->\(ip)",
                        title: "hosts dosyası ele geçirme: \(domain)",
                        detail: "\(domain) alan adı \(ip) adresine yönlendiriliyor (olası kimlik avı/engelleme).",
                        path: hostsFile, severity: .malicious, category: .hostsHijack))
                }
            }
        }
        return threats
    }
}
