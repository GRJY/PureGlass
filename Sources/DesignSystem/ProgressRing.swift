import SwiftUI

/// Tarama/temizlik ilerlemesi için dairesel gösterge.
struct ProgressRing: View {
    /// 0...1 aralığı.
    var progress: Double
    var lineWidth: CGFloat = 12
    var size: CGFloat = 120
    /// true ise: ilerleme sabit kalsa bile dönen bir parıltı gösterir (büyük klasör
    /// ölçülürken "donmuş" görünmez).
    var animating: Bool = false

    @State private var spin = false

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

            if animating {
                Circle()
                    .trim(from: 0, to: 0.12)
                    .stroke(
                        DS.Palette.accent.opacity(0.9),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                            spin = true
                        }
                    }
            }

            Text(clamped, format: .percent.precision(.fractionLength(0)))
                .font(.dsTitle)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("İlerleme")
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }

    private var clamped: Double { max(0, min(1, progress)) }
}
