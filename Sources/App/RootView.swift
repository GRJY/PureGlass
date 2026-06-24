import SwiftUI

/// Uygulama kök görünümü: glass kenar çubuğu + detay (ContentView),
/// şeffaf pencere ayarıyla.
struct RootView: View {
    var body: some View {
        ContentView()
            .background(
                WindowConfigurator().frame(width: 0, height: 0)
            )
    }
}

#Preview {
    RootView()
        .frame(width: 1000, height: 700)
}
