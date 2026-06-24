import SwiftUI

/// Uygulama kök görünümü.
/// Şeffaf cam zemin (NSVisualEffectView) + içerik + pencere şeffaflık ayarı.
/// FAZ 1'de içerik = tasarım sistemi showcase'i. FAZ 6'da gerçek navigasyona dönüşecek.
struct RootView: View {
    var body: some View {
        ZStack {
            // Pencere şeffaflığı (arkadaki masaüstünü örnekleyen cam zemin).
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            ShowcaseView()

            // NSWindow'u şeffaf yapan görünmez yardımcı.
            WindowConfigurator()
                .frame(width: 0, height: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView()
        .frame(width: 920, height: 720)
}
