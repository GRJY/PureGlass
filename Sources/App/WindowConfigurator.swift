import SwiftUI
import AppKit

/// Barındıran `NSWindow`'a erişip şeffaflık ve sürükleme davranışını ayarlar.
/// Görünmez (0×0) bir yardımcı view olarak yerleştirilir.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
