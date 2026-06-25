import SwiftUI
import AppKit
import Observation

/// Diski arka planda 5 sn'de bir sorgulayan canlı disk gözlemcisi.
@MainActor
@Observable
final class DiskMonitor {
    var free: Int64 = 0
    var total: Int64 = 0
    var purgeable: Int64 = 0

    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        refresh()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.refresh()
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    func refresh() {
        let url = URL(filePath: "/")
        let v = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey
        ])
        let important = Int64(v?.volumeAvailableCapacityForImportantUsage ?? 0)  // boşaltılabilir dahil
        let plain = Int64(v?.volumeAvailableCapacity ?? 0)
        total = Int64(v?.volumeTotalCapacity ?? 0)
        free = important
        purgeable = max(0, important - plain)
    }
}

/// Menü çubuğundan açılan tek parça Liquid Glass panel.
/// Barındıran NSPanel tam şeffaf; bu kart tek gerçek cam yüzeydir.
struct MenuPanelView: View {
    let model: AppViewModel
    var onOpenMain: () -> Void = {}

    @State private var disk = DiskMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            header
            diskMetrics
            VStack(spacing: 2) {
                row("Hızlı Tarama", "magnifyingglass") {
                    model.selectedSection = .smartScan
                    onOpenMain()
                    Task { await model.scan() }
                }
                row("Güvenlik Taraması", "shield.lefthalf.filled") {
                    model.selectedSection = .security
                    onOpenMain()
                }
                row("Disk Haritası", "chart.pie") {
                    model.selectedSection = .spaceLens
                    onOpenMain()
                }
                row("Uygulama Kaldırıcı", "trash.square") {
                    model.selectedSection = .uninstaller
                    onOpenMain()
                }
            }
            Divider().opacity(0.3)
            footer
        }
        .padding(DS.Spacing.l)
        .frame(width: 320)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(10)
        .task { disk.start() }
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

    // MARK: - Canlı disk metrikleri

    private var diskMetrics: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack {
                Label("Depolama", systemImage: "internaldrive")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    openStorageSettings()
                } label: {
                    Label("Sistem Ayarları", systemImage: "gearshape")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Sistem Ayarları → Depolama'yı aç")
            }

            ProgressView(value: disk.usedFraction)
                .tint(disk.usedFraction > 0.9 ? DS.Palette.danger
                      : disk.usedFraction > 0.75 ? DS.Palette.caution : DS.Palette.accent)

            HStack(spacing: DS.Spacing.m) {
                metric("Boş", disk.free.formattedBytes, DS.Palette.safe)
                metric("Kullanılan", disk.used.formattedBytes, .primary)
                if disk.purgeable > 0 {
                    metric("Boşaltılabilir", disk.purgeable.formattedBytes, DS.Palette.accent)
                }
            }
            Text("Toplam \(disk.total.formattedBytes) • her 5 sn'de güncellenir")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
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

    private func openStorageSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.Storage",
            "x-apple.systempreferences:com.apple.SystemSettings.GeneralStorageSettings",
            "x-apple.systempreferences:com.apple.settings.General"
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
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
            .modifier(HoverHighlight())
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
