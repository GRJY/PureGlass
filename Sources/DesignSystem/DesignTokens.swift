import SwiftUI

/// PureGlass tasarım jetonları (Design System).
/// Hedef: canlı, akıcı, net, taze. Tutarlı boşluk/yarıçap/animasyon/renk.
enum DS {
    /// 4-pt ızgara.
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
    }

    enum Radius {
        static let s: CGFloat = 10
        static let m: CGFloat = 16
        static let l: CGFloat = 22
        static let xl: CGFloat = 28
    }

    enum Anim {
        static let snappy: Animation = .snappy(duration: 0.32)
        static let bouncy: Animation = .bouncy(duration: 0.5)
        static let smooth: Animation = .smooth(duration: 0.4)
    }

    enum Palette {
        static let accent = Color.accentColor
        // Risk renkleri (RiskLevel ile eşlenir).
        static let safe = Color.green
        static let caution = Color.yellow
        static let danger = Color.red
    }
}

extension Font {
    /// Büyük başlıklar için yuvarlatılmış görünüm.
    static func dsDisplay(_ size: CGFloat = 40) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static let dsTitle = Font.system(.title2, design: .rounded).weight(.semibold)
    static let dsSection = Font.system(.headline, design: .rounded)
    /// Dosya yolları / canlı log için tek aralıklı.
    static let dsMono = Font.system(.callout, design: .monospaced)
}
