import SwiftUI

@main
struct PureGlassApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 920, minHeight: 640)
        }
        // Başlık çubuğunu ve toolbar arka planını kaldırır → tam şeffaf kabuk.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
