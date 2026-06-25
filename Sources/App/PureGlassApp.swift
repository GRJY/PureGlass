import SwiftUI

@main
struct PureGlassApp: App {
    // Menü çubuğu (✨) + paylaşılan durum AppDelegate'te yönetilir.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(model: delegate.model)
                .frame(minWidth: 960, minHeight: 660)
        }
        // Başlık çubuğunu ve toolbar arka planını kaldırır → tam şeffaf kabuk.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 760)
    }
}
