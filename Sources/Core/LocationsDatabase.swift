import Foundation

/// Taranabilir bir temizlik konumu tanımı.
/// `url` taranacak KÖK dizindir; silinecek öğeler bu kökün altındaki çocuklardır.
/// (Kökün kendisi asla silinmez — bkz. `SafetyGuard`.)
public struct CleanLocation: Identifiable, Sendable, Hashable {
    public let id: String
    public let category: ScanCategory
    public let title: String
    public let url: URL
    public let risk: RiskLevel
    public let requiresFullDiskAccess: Bool
    public let requiresRoot: Bool
    public let details: String

    public init(
        id: String,
        category: ScanCategory,
        title: String,
        url: URL,
        risk: RiskLevel,
        requiresFullDiskAccess: Bool,
        requiresRoot: Bool,
        details: String
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.url = url
        self.risk = risk
        self.requiresFullDiskAccess = requiresFullDiskAccess
        self.requiresRoot = requiresRoot
        self.details = details
    }
}

/// Tüm temizlik konumlarının tek doğruluk kaynağı.
/// Yollar `~` içermez (ev dizininden mutlak olarak üretilir).
/// FAZ 6'da kategoriler genişletilecek; burası kasıtlı olarak genişlemeye açık.
public struct LocationsDatabase: Sendable {
    public let locations: [CleanLocation]
    /// "Sistem Verileri" geniş dökümü (risk-sınıflı, manuel temizlik için).
    public let systemData: [CleanLocation]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        var l: [CleanLocation] = []
        func add(
            _ id: String,
            _ category: ScanCategory,
            _ title: String,
            _ relativeToHome: String? = nil,
            absolute: String? = nil,
            risk: RiskLevel = .safe,
            fda: Bool = true,
            root: Bool = false,
            _ details: String
        ) {
            let url: URL
            if let rel = relativeToHome {
                url = home.appending(path: rel)
            } else {
                url = URL(filePath: absolute!)
            }
            l.append(CleanLocation(
                id: id, category: category, title: title, url: url, risk: risk,
                requiresFullDiskAccess: fda, requiresRoot: root, details: details
            ))
        }

        // --- Kullanıcı alanı (yeşil, FDA ile) ---
        add("user.cache", .userCache, "Kullanıcı Önbelleği",
            "Library/Caches",
            "Uygulamaların yeniden ürettiği geçici önbellek dosyaları.")
        add("user.logs", .userLogs, "Kullanıcı Günlükleri",
            "Library/Logs",
            "Birikmiş uygulama günlükleri; silmek uygulamaları etkilemez.")
        add("trash.user", .trash, "Çöp Kutusu",
            ".Trash",
            "Çöp kutusundaki öğeler kalıcı olarak silinir.")

        // --- Geliştirici artıkları ---
        add("xcode.deriveddata", .developerJunk, "Xcode DerivedData",
            "Library/Developer/Xcode/DerivedData",
            "Derleme ara ürünleri; Xcode yeniden üretir.")
        add("xcode.archives", .developerJunk, "Xcode Arşivleri",
            "Library/Developer/Xcode/Archives", risk: .caution,
            "Dağıtım arşivleri — istenen sürümleri kaybetmemek için dikkat.")
        add("xcode.devicesupport", .developerJunk, "iOS DeviceSupport",
            "Library/Developer/Xcode/iOS DeviceSupport",
            "Eski iOS sürümleri için sembol verisi; gerekirse yeniden indirilir.")
        add("coresim.caches", .developerJunk, "Simulator Önbelleği",
            "Library/Developer/CoreSimulator/Caches",
            "Simülatör önbelleği.")

        // --- Paket yöneticisi önbellekleri (ev kökünde, ~/Library/Caches ile çakışmaz) ---
        add("npm.cache", .packageManagerCache, "npm Önbelleği",
            ".npm/_cacache",
            "npm indirme önbelleği.")
        add("generic.cache", .packageManagerCache, "~/.cache",
            ".cache",
            "Çeşitli CLI araçlarının ortak önbellek dizini.")

        // --- Mail ekleri (dikkat) ---
        add("mail.attachments", .mailAttachments, "Mail Ekleri",
            "Library/Mail", risk: .caution,
            "İndirilen mail eklerinin yerel kopyaları.")

        // --- Sistem alanı (root gerektirir — FAZ 9'da etkinleşecek) ---
        add("system.cache", .systemCache, "Sistem Önbelleği",
            absolute: "/Library/Caches", risk: .caution, fda: true, root: true,
            "Sistem geneli önbellek; root gerektirir.")
        add("system.logs", .systemLogs, "Sistem Günlükleri",
            absolute: "/private/var/log", risk: .caution, fda: true, root: true,
            "Sistem günlükleri; root gerektirir.")

        self.locations = l

        // --- "Sistem Verileri" geniş döküm (risk-sınıflı, MANUEL temizlik için) ---
        // macOS'un "Sistem Verileri" kategorisini oluşturan büyük katkıları gösterir.
        var sd: [CleanLocation] = []
        func addSD(_ id: String, _ category: ScanCategory, _ title: String,
                   _ relativeToHome: String? = nil, absolute: String? = nil,
                   risk: RiskLevel = .safe, root: Bool = false, _ details: String) {
            let url = relativeToHome != nil ? home.appending(path: relativeToHome!) : URL(filePath: absolute!)
            sd.append(CleanLocation(id: id, category: category, title: title, url: url, risk: risk,
                                    requiresFullDiskAccess: true, requiresRoot: root, details: details))
        }
        addSD("sd.user.cache", .userCache, "Kullanıcı Önbelleği", "Library/Caches", risk: .safe,
              "Geçici önbellek; uygulamalar yeniden üretir.")
        addSD("sd.user.logs", .userLogs, "Kullanıcı Günlükleri", "Library/Logs", risk: .safe,
              "Uygulama günlükleri; güvenle silinebilir.")
        addSD("sd.trash", .trash, "Çöp Kutusu", ".Trash", risk: .safe, "Çöp kutusu içeriği.")
        addSD("sd.developer", .developerJunk, "Geliştirici (Kullanıcı — Xcode)", "Library/Developer", risk: .caution,
              "DerivedData, DeviceSupport, Simulators, Arşivler.")
        addSD("sd.system.developer", .developerJunk, "Geliştirici (Sistem — Simülatör Ortamları)",
              absolute: "/Library/Developer", risk: .caution, root: true,
              "iOS simülatör çalıştırma ortamları (runtimes) — genelde en büyük 'Sistem Verisi'. Xcode yeniden indirir.")
        addSD("sd.mail", .mailAttachments, "Mail", "Library/Mail", risk: .caution,
              "Mail verileri ve indirilen ekler.")
        addSD("sd.containers", .containers, "Konteynerler", "Library/Containers", risk: .danger,
              "Sandbox'lı uygulama verileri — silersen o uygulamanın verisi kaybolur.")
        addSD("sd.groupcontainers", .containers, "Grup Konteynerleri", "Library/Group Containers", risk: .danger,
              "Paylaşılan uygulama grubu verileri.")
        addSD("sd.appsupport", .applicationData, "Uygulama Verileri", "Library/Application Support", risk: .danger,
              "Uygulamaların kalıcı verileri (iOS yedekleri dahil). Dikkatli seç.")
        addSD("sd.system.cache", .systemCache, "Sistem Önbelleği", absolute: "/Library/Caches", risk: .caution, root: true,
              "Sistem geneli önbellek (root gerekir).")
        addSD("sd.system.logs", .systemLogs, "Sistem Günlükleri", absolute: "/private/var/log", risk: .caution, root: true,
              "Sistem günlükleri (root gerekir).")
        self.systemData = sd
    }

    /// Yalnızca root gerektirmeyen (kullanıcı alanı) konumlar.
    public var userSpaceLocations: [CleanLocation] {
        locations.filter { !$0.requiresRoot }
    }

    public func locations(in category: ScanCategory) -> [CleanLocation] {
        locations.filter { $0.category == category }
    }
}
