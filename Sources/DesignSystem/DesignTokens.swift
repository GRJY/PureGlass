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
    /// Inter (değişken font). Uygulama açılışında kaydedilir (AppDelegate).
    static func inter(_ size: CGFloat, relativeTo style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .custom("InterVariable", size: size, relativeTo: style).weight(weight)
    }

    /// Büyük başlıklar.
    static func dsDisplay(_ size: CGFloat = 40) -> Font { inter(size, relativeTo: .largeTitle, weight: .bold) }
    static let dsTitle = inter(20, relativeTo: .title2, weight: .semibold)
    static let dsSection = inter(17, relativeTo: .headline, weight: .semibold)

    // Inter gövde/yardımcı stilleri (sistem text-style'larının Inter karşılıkları)
    static let iBody = inter(13, relativeTo: .body)
    static let iHeadline = inter(13, relativeTo: .headline, weight: .semibold)
    static let iSubheadline = inter(12, relativeTo: .subheadline)
    static let iCallout = inter(12, relativeTo: .callout)
    static let iCaption = inter(11, relativeTo: .caption)
    static let iCaption2 = inter(10, relativeTo: .caption2)
    static let iTitle3 = inter(17, relativeTo: .title3, weight: .semibold)

    /// Dosya yolları / canlı log için tek aralıklı (Inter mono değildir → sistem mono kalır).
    static let dsMono = Font.system(.callout, design: .monospaced)
}
