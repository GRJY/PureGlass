import SwiftUI
import PureGlassKit

extension LogLine {
    /// CleanEvent → canlı log satırı eşlemesi.
    init(event: CleanEvent) {
        let status: LogLine.Status
        switch event.outcome {
        case .trashed: status = .deleted
        case .skippedUnsafe: status = .skipped
        case .failed: status = .failed
        }
        self.init(path: event.url.path, status: status)
    }
}

extension Int64 {
    /// İnsan-okunur boyut (örn. "1,2 GB").
    var formattedBytes: String {
        self.formatted(.byteCount(style: .file))
    }
}

extension RiskLevel {
    var uiColor: Color {
        switch self {
        case .safe: DS.Palette.safe
        case .caution: DS.Palette.caution
        case .danger: DS.Palette.danger
        }
    }
}
