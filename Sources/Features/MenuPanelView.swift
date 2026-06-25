import SwiftUI
import AppKit

/// Menü çubuğundan açılan tek parça Liquid Glass panel.
/// Barındıran NSPanel tam şeffaf; bu kart tek gerçek cam yüzeydir (glass-on-glass yok).
struct MenuPanelView: View {
    let model: AppViewModel
    var onOpenMain: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            header
            freeSpace
            VStack(spacing: 2) {
                row("Hızlı Tarama", "magnifyingglass") {
                    model.selectedSection = .smartScan
                    onOpenMain()
                    Task { await model.scan() }
                }
                row("Disk Haritası", "chart.pie") {
                    model.selectedSection = .spaceLens
                    onOpenMain()
                }
                row("Uygulama Kaldırıcı", "trash.square") {
                    model.selectedSection = .uninstaller
                    onOpenMain()
                }
                row("Pencereyi Aç", "macwindow") { onOpenMain() }
            }
            Divider().opacity(0.3)
            HStack {
                Text("Lokalde çalışır • telemetri yok")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Çık") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DS.Spacing.l)
        .frame(width: 300)
        // Tek gerçek Liquid Glass yüzey; arkadaki NSPanel şeffaf olduğu için masaüstünü örnekler.
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(10)   // gölge/parlama payı (panel fittingSize bunu içerir)
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: "sparkles")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("PureGlass").font(.headline)
                Text("Hızlı temizlik").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var freeSpace: some View {
        let (free, total) = DiskSpace.current()
        let used = total > 0 ? Double(total - free) / Double(total) : 0
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text("Boş alan").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(free.formattedBytes) / \(total.formattedBytes)")
                    .font(.caption.monospacedDigit())
            }
            ProgressView(value: used)
                .tint(used > 0.9 ? DS.Palette.danger : DS.Palette.accent)
        }
    }

    private func row(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: symbol).frame(width: 22)
                Text(title)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, DS.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
    }
}

/// Satır butonu: bas/üzerine gel vurgusu.
private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color.primary.opacity(0.15) : Color.clear,
                in: .rect(cornerRadius: 8)
            )
            .hoverEffect()
    }
}

private extension View {
    @ViewBuilder func hoverEffect() -> some View {
        modifier(HoverHighlight())
    }
}

private struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(hovering ? Color.primary.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 8))
            .onHover { hovering = $0 }
    }
}

/// Önyükleme diskinin boş/toplam kapasitesi.
enum DiskSpace {
    static func current() -> (free: Int64, total: Int64) {
        let url = URL(filePath: "/")
        let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ])
        let free = Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        return (free, total)
    }
}
