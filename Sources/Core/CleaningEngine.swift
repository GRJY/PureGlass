import Foundation

/// Tek bir öğe için temizlik sonucu (canlı log için).
public struct CleanEvent: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case trashed
        case skippedUnsafe(String)   // SafetyGuard reddetti
        case failed(String)          // Çöp'e taşıma hatası
    }
    public let url: URL
    public let size: Int64
    public let outcome: Outcome
}

/// Bir temizlik turunun özeti.
public struct CleanReport: Sendable {
    public private(set) var trashedCount = 0
    public private(set) var skippedCount = 0
    public private(set) var failedCount = 0
    public private(set) var bytesReclaimed: Int64 = 0
    public private(set) var events: [CleanEvent] = []

    public init() {}

    mutating func record(_ event: CleanEvent) {
        events.append(event)
        switch event.outcome {
        case .trashed:
            trashedCount += 1
            bytesReclaimed += event.size
        case .skippedUnsafe:
            skippedCount += 1
        case .failed:
            failedCount += 1
        }
    }
}

/// Öğeleri güvenle Çöp'e taşıyan motor.
///
/// İlkeler:
/// - **Trash-first:** kalıcı silme yok; her şey geri alınabilir Çöp'e gider.
/// - **Silmeden hemen önce doğrulama:** `SafetyGuard.validate` (TOCTOU koruması).
/// - **Hata toleransı:** bir öğe başarısız olursa atla, raporla, devam et.
/// - **Canlı olay:** her öğe için yol + sonuç yayınlanır.
public struct CleaningEngine: Sendable {
    let safety: SafetyGuard
    let trash: @Sendable (URL) throws -> Void

    public init(
        safety: SafetyGuard,
        trash: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
    ) {
        self.safety = safety
        self.trash = trash
    }

    /// Verilen öğeleri sırayla Çöp'e taşır (canlı log akıcı kalsın diye sıralı).
    public func clean(
        _ items: [FileItem],
        onEvent: (@Sendable (CleanEvent) async -> Void)? = nil
    ) async -> CleanReport {
        var report = CleanReport()
        for item in items {
            if Task.isCancelled { break }
            let event = trashOne(url: item.url, size: item.size)
            report.record(event)
            await onEvent?(event)
        }
        return report
    }

    /// Tek bir öğeyi doğrulayıp Çöp'e taşır.
    func trashOne(url: URL, size: Int64) -> CleanEvent {
        // 1) Güvenlik kapısı — silmeden HEMEN önce (TOCTOU).
        do {
            try safety.validate(url)
        } catch {
            let reason = (error as? SafetyGuard.Violation)?.description ?? "\(error)"
            return CleanEvent(url: url, size: size, outcome: .skippedUnsafe(reason))
        }
        // 2) Çöp'e taşı.
        do {
            try trash(url)
            return CleanEvent(url: url, size: size, outcome: .trashed)
        } catch {
            return CleanEvent(url: url, size: size, outcome: .failed(error.localizedDescription))
        }
    }
}
