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
    }

    /// Yalnızca root gerektirmeyen (kullanıcı alanı) konumlar.
    public var userSpaceLocations: [CleanLocation] {
        locations.filter { !$0.requiresRoot }
    }

    public func locations(in category: ScanCategory) -> [CleanLocation] {
        locations.filter { $0.category == category }
    }
}
