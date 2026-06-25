import Foundation

/// Root (yönetici) yetkisi gerektiren sistem öğeleri için temizlik mantığı.
///
/// Bu tip SADECE doğrulama + güvenli komut kurar; yetkili ÇALIŞTIRMA UI katmanındadır
/// (NSAppleScript "with administrator privileges"). Böylece:
/// - mantık tamamen test edilebilir (saf, yan etkisiz),
/// - komut yalnızca daha KATI bir `SafetyGuard`'dan (yalnız sistem-cache/log kökleri)
///   geçen yollar için kurulur,
/// - tek tırnak kaçışı + `--` ile kabuk enjeksiyonu engellenir.
///
/// Not: root-sahipli cache/log dosyaları Çöp'e taşınamaz; kalıcı silinir (yeniden üretilir).
public struct PrivilegedCleaner: Sendable {
    let safety: SafetyGuard

    public init(safety: SafetyGuard) {
        self.safety = safety
    }

    /// Yalnızca sistem (requiresRoot) konumlarının köklerinden bir koruyucu kurar.
    public init(database: LocationsDatabase) {
        let systemRoots = database.locations.filter(\.requiresRoot).map(\.url)
        self.safety = SafetyGuard(allowedRoots: systemRoots)
    }

    /// Öğeleri güvenli/güvensiz diye ayırır.
    public func partition(_ items: [FileItem]) -> (valid: [FileItem], skipped: [FileItem]) {
        var valid: [FileItem] = []
        var skipped: [FileItem] = []
        for item in items {
            if safety.isValid(item.url) { valid.append(item) } else { skipped.append(item) }
        }
        return (valid, skipped)
    }

    /// Doğrulanmış yollar için enjeksiyon-güvenli `rm` komutu kurar (boşsa nil).
    public func buildCommand(for urls: [URL]) -> String? {
        guard !urls.isEmpty else { return nil }
        let quoted = urls.map { Self.shellQuote($0.path) }
        return "/bin/rm -rf -- " + quoted.joined(separator: " ")
    }

    /// Tek tırnaklı, kaçışlı kabuk argümanı: ' → '\''
    static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
