import SwiftUI

/// Tarama/temizlik ilerlemesi için dairesel gösterge.
struct ProgressRing: View {
    /// 0...1 aralığı.
    var progress: Double
    var lineWidth: CGFloat = 12
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    DS.Palette.accent.gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(DS.Anim.smooth, value: clamped)

            Text(clamped, format: .percent.precision(.fractionLength(0)))
                .font(.dsTitle)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(L("İlerleme", "Progress"))
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }

    private var clamped: Double { max(0, min(1, progress)) }
}
