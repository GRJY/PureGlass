import SwiftUI
import AppKit

/// Pencere arka planı için `NSVisualEffectView` sarmalayıcı.
///
/// Not (macOS 26 / Tahoe): `NSGlassEffectView`'in doğrudan SwiftUI içeriğine
/// sarılması bazı durumlarda boş/yanlış tonlanmış içerik üretiyor. Bu yüzden
/// pencere ŞEFFAFLIĞINI kararlı olan `NSVisualEffectView` ile sağlıyoruz;
/// Liquid Glass (`.glassEffect`) yalnızca içteki kontrollere uygulanıyor.
///
/// `.behindWindow` harmanlama, pencerenin ARKASINDAKİ masaüstünü örnekleyerek
/// canlı, şeffaf cam efektini verir.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
