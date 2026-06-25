import SwiftUI

/// Uygulama kök görünümü: glass kenar çubuğu + detay (ContentView),
/// şeffaf pencere ayarıyla. Durum yukarıdan (App) paylaşılır.
struct RootView: View {
    let model: AppViewModel

    var body: some View {
        ContentView(model: model)
            .background(
                WindowConfigurator().frame(width: 0, height: 0)
            )
    }
}

#Preview {
    RootView(model: AppViewModel())
        .frame(width: 1000, height: 700)
}
