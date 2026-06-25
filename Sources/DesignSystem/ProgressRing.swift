import SwiftUI

/// Tarama/temizlik ilerlemesi için dairesel gösterge.
///
/// `animating == true` iken: ilerleme dolgusu yerine ZAMAN-TABANLI sürekli dönen bir
/// sweep gösterir (`TimelineView(.animation)`). Böylece uzun süren bir adımda ilerleme
/// değeri sabit kalsa bile halka asla "donmuş" görünmez. Yüzde, ortada metin olarak kalır.
struct ProgressRing: View {
    /// 0...1 aralığı.
    var progress: Double
    var lineWidth: CGFloat = 12
    var size: CGFloat = 120
    var animating: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.18), lineWidth: lineWidth)

            if animating {
                spinner
            } else {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        DS.Palette.accent.gradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(DS.Anim.smooth, value: clamped)
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

    /// Zaman-tabanlı sürekli dönen sweep — state'ten bağımsız, asla durmaz.
    private var spinner: some View {
        TimelineView(.animation) { timeline in
            let period = 1.1
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = (t.truncatingRemainder(dividingBy: period) / period) * 360.0
            Circle()
                .trim(from: 0, to: 0.32)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [DS.Palette.accent.opacity(0), DS.Palette.accent]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(angle))
        }
    }

    private var clamped: Double { max(0, min(1, progress)) }
}
