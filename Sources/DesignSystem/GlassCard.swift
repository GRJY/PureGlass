import SwiftUI

/// Tutarlı dolgu ve köşe yarıçapıyla Liquid Glass kart kabı.
/// Glass yalnızca fonksiyonel/kap katmanında kullanılır (içerik listelerinde değil).
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = DS.Radius.l
    var padding: CGFloat = DS.Spacing.l
    /// true ise kart, kabının yüksekliğini doldurur (satırdaki kartları eşitlemek için).
    var fill: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: fill ? .infinity : nil, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
