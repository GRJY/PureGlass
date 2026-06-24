import Foundation

/// Temizlik kategorileri. `symbolName` bir SF Symbol adıdır (UI bağımlılığı değil,
/// yalnızca string); renkler UI'da eşlenir.
public enum ScanCategory: String, Sendable, CaseIterable, Codable {
    case userCache
    case systemCache
    case userLogs
    case systemLogs
    case developerJunk
    case packageManagerCache
    case trash
    case mailAttachments
    case browserData
    case appLeftovers
    case largeOldFiles

    public var title: String {
        switch self {
        case .userCache: return "Kullanıcı Önbelleği"
        case .systemCache: return "Sistem Önbelleği"
        case .userLogs: return "Kullanıcı Günlükleri"
        case .systemLogs: return "Sistem Günlükleri"
        case .developerJunk: return "Geliştirici Artıkları"
        case .packageManagerCache: return "Paket Yöneticisi Önbelleği"
        case .trash: return "Çöp Kutuları"
        case .mailAttachments: return "Mail Ekleri"
        case .browserData: return "Tarayıcı Verileri"
        case .appLeftovers: return "Uygulama Artıkları"
        case .largeOldFiles: return "Büyük & Eski Dosyalar"
        }
    }

    public var symbolName: String {
        switch self {
        case .userCache: return "person.crop.circle.badge.clock"
        case .systemCache: return "gearshape.2"
        case .userLogs: return "doc.text"
        case .systemLogs: return "doc.text.below.ecg"
        case .developerJunk: return "hammer"
        case .packageManagerCache: return "shippingbox"
        case .trash: return "trash"
        case .mailAttachments: return "paperclip"
        case .browserData: return "safari"
        case .appLeftovers: return "app.badge"
        case .largeOldFiles: return "externaldrive.badge.exclamationmark"
        }
    }

    public var defaultRisk: RiskLevel {
        switch self {
        case .userCache, .systemCache, .userLogs, .systemLogs,
             .developerJunk, .packageManagerCache, .trash, .browserData:
            return .safe
        case .mailAttachments, .appLeftovers:
            return .caution
        case .largeOldFiles:
            return .caution
        }
    }
}
