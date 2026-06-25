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
            // İçeriği (kaydırıcı vb.) sürüklerken pencere kaymasın; yalnızca başlık çubuğundan taşınır.
            window.isMovableByWindowBackground = false

            // TR/EN geçişini başlık çubuğunun SAĞ ucuna native olarak yerleştir
            // (içeriğe/kaydırma çubuğuna binmez).
            if !window.titlebarAccessoryViewControllers.contains(where: { $0.identifier?.rawValue == "langToggle" }) {
                let accessory = NSTitlebarAccessoryViewController()
                accessory.identifier = NSUserInterfaceItemIdentifier("langToggle")
                accessory.layoutAttribute = .trailing
                let host = NSHostingView(rootView: LanguageToggle().padding(.horizontal, 10).padding(.vertical, 3))
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                accessory.view = host
                window.addTitlebarAccessoryViewController(accessory)
            }

            AppDelegate.shared?.registerMainWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
