import SwiftUI
import AppKit
import CoreText

/// Uygulama yaşam döngüsü + paylaşılan durum + menü çubuğu denetleyicisi.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    let model = AppViewModel()
    private var statusBar: StatusBarController?
    weak var mainWindow: NSWindow?

    override init() {
        super.init()
        AppDelegate.shared = self
        Self.registerFonts()
    }

    private static func registerFonts() {
        for name in ["InterVariable", "InterVariable-Italic"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(model: model)
    }

    /// Ana pencere kapatılınca yok edilmesin ki menüden tekrar açılabilsin.
    func registerMainWindow(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        mainWindow = window
    }

    func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = mainWindow {
            w.deminiaturize(nil)
            w.makeKeyAndOrderFront(nil)
        }
    }
}

/// Menü çubuğu ✨ ikonu + TAM ŞEFFAF (borderless, clear) panel.
/// Panelin arkası tamamen şeffaftır; yalnızca içteki Liquid Glass kart yüzer.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private let host: NSHostingView<MenuPanelView>
    private var monitor: Any?

    init(model: AppViewModel) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        host = NSHostingView(rootView: MenuPanelView(model: model))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.autoresizingMask = [.width, .minYMargin]   // panel boyu değişince üst kenara sabit kal

        panel = NSPanel(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear        // ← arka plan tam şeffaf
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.contentView = host

        super.init()

        // Gerçek closure'ları bağla: ana pencereyi aç + sekme değişince paneli
        // yumuşak animasyonla yeniden boyutlandır (üst kenar sabit).
        host.rootView = MenuPanelView(
            model: model,
            onOpenMain: { AppDelegate.shared?.openMain() },
            onSize: { [weak self] size in self?.resizePanel(to: size) }
        )

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "PureGlass")
            button.action = #selector(toggle)
            button.target = self
        }
    }

    @objc private func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func show() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        if let host = panel.contentView { panel.setContentSize(host.fittingSize) }

        let rect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = rect.midX - panel.frame.width / 2
        let y = rect.minY - panel.frame.height - 4
        if let screen = buttonWindow.screen {
            x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - panel.frame.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()

        // Panel dışına tıklayınca kapat (kendi uygulamamızın olayları bu monitöre düşmez).
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func hide() {
        panel.orderOut(nil)
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    /// İçerik yüksekliği değişince paneli yumuşak animasyonla yeniden boyutlandırır.
    /// Üst kenar sabit kalır (panel menü çubuğundan aşağı sarkar).
    private func resizePanel(to size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        guard panel.isVisible else {
            host.frame = CGRect(origin: .zero, size: size)
            panel.setContentSize(size)
            return
        }

        let topY = panel.frame.maxY
        var f = panel.frame
        f.size = size
        f.origin.y = topY - size.height          // üst kenarı sabitle
        // host'u son boyutuna getir, panel içeriğinin üstüne yapıştır (minYMargin korur).
        host.frame = CGRect(x: 0, y: panel.frame.height - size.height, width: size.width, height: size.height)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(f, display: true)
        }
    }
}
