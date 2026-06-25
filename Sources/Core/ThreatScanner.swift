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
        case launchItem      // LaunchAgent/Daemon kalıcılığı (imza doğrulamalı)
        case knownMalware    // bilinen adware/malware göstergesi
        case hostsHijack     // /etc/hosts ele geçirme
        case shellConfig     // ~/.zshrc vb. kabuk başlangıç dosyası
        case cron            // cron görevi
        case emond           // emond olay-monitör kalıcılığı
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

/// Kalıcılık konumlarını tarayan + her çalıştırılabilir öğenin KOD İMZASINI doğrulayan
/// tehdit tarayıcı (KnockKnock yaklaşımı). Offline, gizlilik dostu; bulut antivirüs değildir.
///
/// Mantık:
/// - Apple/Developer-ID/imzalı kalıcı öğeler GÜVENİLİR sayılır (alarm yok).
/// - İmzasız / ad-hoc kalıcı öğeler ŞÜPHELİ.
/// - Bozuk/geçersiz imza ZARARLI işareti.
/// - Yorumlayıcı (sh/python…) çalıştıran görevlerde imza yerine KOMUT içeriği analiz edilir.
/// - Bilinen adware/malware göstergeleri ve hosts ele geçirmesi ayrıca yakalanır.
public struct ThreatScanner: Sendable {
    let launchDirs: [URL]
    let shellConfigs: [URL]
    let cronDir: URL
    let emondRulesDir: URL
    let hostsFile: URL
    let knownAppPaths: [URL]
    let signer: CodeSignatureInspector

    static let knownIndicators: [String] = [
        "genieo", "pirrit", "bundlore", "adload", "vsearch", "spigot", "crossrider",
        "conduit", "installmac", "searchmine", "trovi", "mughthesec", "shlayer",
        "mackeeper", "cpuminer", "xmrig", "keranger", "silversparrow",
        "advancedmaccleaner", "pcvark", "amccleaner"
    ]

    static let sensitiveDomains: [String] = [
        "apple.com", "icloud.com", "mzstatic.com", "malwarebytes", "norton",
        "mcafee", "kaspersky", "virustotal", "objective-see"
    ]

    static let interpreters: Set<String> = [
        "sh", "bash", "zsh", "dash", "ksh", "python", "python3", "perl", "ruby",
        "osascript", "node", "php"
    ]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        launchDirs: [URL]? = nil,
        shellConfigs: [URL]? = nil,
        cronDir: URL = URL(filePath: "/private/var/at/tabs"),
        emondRulesDir: URL = URL(filePath: "/etc/emond.d/rules"),
        hostsFile: URL = URL(filePath: "/etc/hosts"),
        knownAppPaths: [URL]? = nil,
        signer: CodeSignatureInspector = CodeSignatureInspector()
    ) {
        self.launchDirs = launchDirs ?? [
            home.appending(path: "Library/LaunchAgents"),
            URL(filePath: "/Library/LaunchAgents"),
            URL(filePath: "/Library/LaunchDaemons")
        ]
        self.shellConfigs = shellConfigs ?? [
            ".zshrc", ".zprofile", ".zshenv", ".bash_profile", ".bashrc", ".profile"
        ].map { home.appending(path: $0) }
        self.cronDir = cronDir
        self.emondRulesDir = emondRulesDir
        self.hostsFile = hostsFile
        self.knownAppPaths = knownAppPaths ?? [
            URL(filePath: "/Applications/MacKeeper.app"),
            URL(filePath: "/Applications/Advanced Mac Cleaner.app"),
            URL(filePath: "/Applications/MacBooster.app"),
            home.appending(path: "Library/Application Support/MacKeeper")
        ]
        self.signer = signer
    }

    public func scan() async -> [Threat] {
        var threats: [Threat] = []
        let fm = FileManager.default

        // 1) Launch agent/daemon (imza doğrulamalı)
        for dir in launchDirs {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for url in entries where url.pathExtension == "plist" {
                if Task.isCancelled { break }
                if let t = inspectLaunchPlist(url) { threats.append(t) }
            }
        }

        // 2) Kabuk başlangıç dosyaları
        for url in shellConfigs { threats += inspectShellConfig(url) }

        // 3) Cron
        if let entries = try? fm.contentsOfDirectory(at: cronDir, includingPropertiesForKeys: nil, options: []) {
            for url in entries { threats += inspectCron(url) }
        }

        // 4) emond kuralları (nadiren meşru → komutlu kural şüpheli)
        if let entries = try? fm.contentsOfDirectory(at: emondRulesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for url in entries where url.pathExtension == "plist" {
                threats.append(Threat(id: "emond:\(url.path)",
                    title: "emond kuralı: \(url.lastPathComponent)",
                    detail: "emond (Event Monitor) kuralı tanımlı. Nadiren meşru kullanılır; kalıcılık için kötüye kullanılabilir.",
                    path: url, severity: .suspicious, category: .emond))
            }
        }

        // 5) Bilinen PUP/malware uygulamaları
        for url in knownAppPaths where fm.fileExists(atPath: url.path) {
            threats.append(Threat(id: "known:\(url.path)",
                title: "Bilinen istenmeyen yazılım: \(url.lastPathComponent)",
                detail: "Yaygın olarak adware/PUP bilinen bir yazılım.",
                path: url, severity: .malicious, category: .knownMalware))
        }

        // 6) hosts ele geçirme
        if let contents = try? String(contentsOf: hostsFile, encoding: .utf8) {
            threats += inspectHosts(contents)
        }

        return threats.sorted { $0.severity > $1.severity }
    }

    // MARK: - Launch item (imza tabanlı)

    func inspectLaunchPlist(_ url: URL) -> Threat? {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        let label = (dict["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let args = programArguments(dict)
        let joined = args.joined(separator: " ").lowercased()
        let lowerLabel = label.lowercased()

        // a) Bilinen gösterge → zararlı
        for sig in Self.knownIndicators where lowerLabel.contains(sig) || joined.contains(sig) {
            return Threat(id: "launch:\(url.path)", title: "Bilinen zararlı/adware: \(label)",
                detail: "Bilinen tehdit göstergesi '\(sig)' içeriyor.", path: url,
                severity: .malicious, category: .knownMalware)
        }

        guard let program = args.first, !program.isEmpty else { return nil }
        let programName = (program as NSString).lastPathComponent.lowercased()

        // b) Yorumlayıcı çalıştırıyorsa → komut içeriğini analiz et
        if Self.interpreters.contains(programName) {
            if isDropper(joined) {
                return Threat(id: "launch:\(url.path)", title: "İnternetten indirip çalıştıran görev: \(label)",
                    detail: "Kalıcı görev internetten içerik indirip çalıştırıyor (dropper).", path: url,
                    severity: .malicious, category: .launchItem)
            }
            if let pattern = suspiciousCommand(joined) {
                return Threat(id: "launch:\(url.path)", title: "Şüpheli kalıcı görev: \(label)",
                    detail: "Şüpheli komut deseni: \(pattern)", path: url,
                    severity: .suspicious, category: .launchItem)
            }
            return nil
        }

        // c) Gerçek ikili → KOD İMZASINI doğrula (asıl sinyal)
        let programURL = program.hasPrefix("/") ? URL(filePath: program) : url   // göreli yol nadirdir
        let brew = isHomebrew(label: lowerLabel, program: program)
        switch signer.status(of: programURL) {
        case .apple, .developerID, .signed:
            return nil   // güvenilir imza → alarm yok
        case .adhoc, .unsigned:
            // İmzasız/ad-hoc kalıcı öğe. Homebrew gibi bilinen kaynaksa yalnızca bilgi.
            let sev: Threat.Severity = brew ? .info : .suspicious
            let note = brew ? " (Homebrew servisi — bilinen kaynak)" : ""
            return Threat(id: "launch:\(url.path)",
                title: "İmzasız/ad-hoc kalıcı görev: \(label)\(note)",
                detail: "Çalıştırılan ikilinin geçerli kod imzası yok: \(program)",
                path: url, severity: sev, category: .launchItem)
        case .invalid:
            return Threat(id: "launch:\(url.path)", title: "Bozuk imzalı kalıcı görev: \(label)",
                detail: "İmza mevcut ama geçersiz/bozuk: \(program)",
                path: url, severity: .malicious, category: .launchItem)
        case .missing:
            return Threat(id: "launch:\(url.path)", title: "Eksik hedefli kalıcı görev: \(label)",
                detail: "Görevin işaret ettiği ikili bulunamadı (yetim görev): \(program)",
                path: url, severity: .suspicious, category: .launchItem)
        }
    }

    private func isHomebrew(label: String, program: String) -> Bool {
        label.hasPrefix("homebrew.")
            || program.contains("/opt/homebrew/")
            || program.contains("/Cellar/")
            || program.contains("/usr/local/Cellar/")
    }

    private func programArguments(_ dict: [String: Any]) -> [String] {
        if let pa = dict["ProgramArguments"] as? [String] { return pa }
        if let p = dict["Program"] as? String { return [p] }
        return []
    }

    // MARK: - Kabuk / cron komut analizi

    func inspectShellConfig(_ url: URL) -> [Threat] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return suspiciousLines(in: contents, path: url, category: .shellConfig,
                               titlePrefix: "Kabuk başlangıç dosyasında şüpheli komut")
    }

    func inspectCron(_ url: URL) -> [Threat] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return suspiciousLines(in: contents, path: url, category: .cron,
                               titlePrefix: "Cron görevinde şüpheli komut")
    }

    private func suspiciousLines(in contents: String, path: URL, category: Threat.Category, titlePrefix: String) -> [Threat] {
        var threats: [Threat] = []
        for raw in contents.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            let low = line.lowercased()
            if isDropper(low) {
                threats.append(Threat(id: "\(category.rawValue):\(path.path):\(threats.count)",
                    title: titlePrefix, detail: "İndirip çalıştıran komut:\n\(line)",
                    path: path, severity: .malicious, category: category))
            } else if let p = suspiciousCommand(low) {
                threats.append(Threat(id: "\(category.rawValue):\(path.path):\(threats.count)",
                    title: titlePrefix, detail: "Şüpheli desen '\(p)':\n\(line)",
                    path: path, severity: .suspicious, category: category))
            }
        }
        return threats
    }

    /// curl/wget ile indirip kabuğa borulama/eval (klasik dropper).
    private func isDropper(_ low: String) -> Bool {
        let downloads = low.contains("curl ") || low.contains("wget ") || low.contains("curl(")
        let pipeExec = low.contains("|sh") || low.contains("| sh") || low.contains("|bash")
            || low.contains("| bash") || low.contains("|zsh") || low.contains("| zsh")
            || low.contains("eval ")
        return downloads && pipeExec
    }

    private func suspiciousCommand(_ low: String) -> String? {
        let patterns = ["base64 -d", "base64 --decode", "osascript -e", "python -c",
                        "/tmp/", "/private/tmp/", "/var/tmp/", "/users/shared/"]
        return patterns.first { low.contains($0) }
    }

    // MARK: - hosts

    func inspectHosts(_ contents: String) -> [Threat] {
        var threats: [Threat] = []
        for raw in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let ip = parts[0]
            if ip == "127.0.0.1" || ip == "::1" || ip == "0.0.0.0" { continue }
            for domain in parts.dropFirst() {
                let d = domain.lowercased()
                if Self.sensitiveDomains.contains(where: { d.contains($0) }) {
                    threats.append(Threat(id: "hosts:\(d)->\(ip)",
                        title: "hosts dosyası ele geçirme: \(domain)",
                        detail: "\(domain) → \(ip) (hassas alan adı uzak adrese yönlendiriliyor).",
                        path: hostsFile, severity: .malicious, category: .hostsHijack))
                }
            }
        }
        return threats
    }
}
