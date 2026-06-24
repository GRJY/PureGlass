import SwiftUI
import PureGlassKit

/// Risk seviyesini renk + ikon + etiketle gösteren kapsül rozet.
/// `RiskLevel` (Core, UI-bağımsız) burada renge eşlenir.
struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        Label(level.title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, DS.Spacing.s)
            .padding(.vertical, DS.Spacing.xs)
            .glassEffect(.regular.tint(color.opacity(0.30)), in: .capsule)
            .accessibilityLabel("Risk: \(level.title)")
    }

    private var color: Color {
        switch level {
        case .safe: DS.Palette.safe
        case .caution: DS.Palette.caution
        case .danger: DS.Palette.danger
        }
    }

    private var icon: String {
        switch level {
        case .safe: "checkmark.shield.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        }
    }
}
