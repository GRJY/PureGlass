import SwiftUI

@main
struct PureGlassApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 960, minHeight: 660)
        }
        // Başlık çubuğunu ve toolbar arka planını kaldırır → tam şeffaf kabuk.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 760)
    }
}
