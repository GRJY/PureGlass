import Foundation

/// Taramada bulunan tek bir silinebilir öğe (genelde bir konum kökünün üst-düzey çocuğu).
public struct FileItem: Identifiable, Sendable, Hashable {
    public var id: URL { url }
    public let url: URL
    /// Diskte ayrılmış gerçek boyut (geri kazanılacak alan), byte.
    public let size: Int64
    public let isDirectory: Bool
    /// Bu öğenin altındaki dosya sayısı (dizinse özyinelemeli; dosyaysa 1).
    public let fileCount: Int
    public let modificationDate: Date?
    public let category: ScanCategory
    public let risk: RiskLevel

    public init(
        url: URL, size: Int64, isDirectory: Bool, fileCount: Int,
        modificationDate: Date?, category: ScanCategory, risk: RiskLevel
    ) {
        self.url = url
        self.size = size
        self.isDirectory = isDirectory
        self.fileCount = fileCount
        self.modificationDate = modificationDate
        self.category = category
        self.risk = risk
    }
}

/// Bir konumun tarama sonucu.
public struct CategoryScanResult: Identifiable, Sendable {
    public var id: String { locationID }
    public let locationID: String
    public let category: ScanCategory
    public let title: String
    public let url: URL
    public let risk: RiskLevel
    public let items: [FileItem]
    /// Dizin okunamadıysa (izin yok) false. Var olmayan dizinde true (silinecek bir şey yok).
    public let isAccessible: Bool

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    public var itemCount: Int { items.count }
    public var totalFileCount: Int { items.reduce(0) { $0 + $1.fileCount } }

    public init(
        locationID: String, category: ScanCategory, title: String, url: URL,
        risk: RiskLevel, items: [FileItem], isAccessible: Bool
    ) {
        self.locationID = locationID
        self.category = category
        self.title = title
        self.url = url
        self.risk = risk
        self.items = items
        self.isAccessible = isAccessible
    }
}

/// Tarama ilerleme anlık görüntüsü.
public struct ScanProgress: Sendable {
    public let completedLocations: Int
    public let totalLocations: Int
    public let currentTitle: String
    public let bytesFound: Int64

    public var fraction: Double {
        totalLocations == 0 ? 0 : Double(completedLocations) / Double(totalLocations)
    }
}
