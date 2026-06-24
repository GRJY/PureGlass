import Foundation

/// Bir dosyanın/işlemin silinme riski.
///
/// Renk eşlemesi kasıtlı olarak burada DEĞİL — Core katmanı UI'dan bağımsız kalır.
/// Renkler DesignSystem'de (`RiskBadge`) eşleştirilir.
public enum RiskLevel: String, Sendable, CaseIterable, Codable {
    /// Yeşil — güvenle silinebilir (cache, log, geçici dosya). Otomatik seçilebilir.
    case safe
    /// Sarı — onay gerektirir (büyük/eski dosyalar, yedekler). Otomatik seçilmez.
    case caution
    /// Kırmızı — asla otomatik; korumalı veya yüksek riskli.
    case danger

    public var title: String {
        switch self {
        case .safe: return "Güvenli"
        case .caution: return "Dikkat"
        case .danger: return "Riskli"
        }
    }

    /// Sıralama/önceliklendirme için (düşük = daha güvenli).
    public var severity: Int {
        switch self {
        case .safe: return 0
        case .caution: return 1
        case .danger: return 2
        }
    }
}
