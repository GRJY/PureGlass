import SwiftUI
import AppKit
import Observation
import PureGlassKit

/// Menü panelinin canlı sistem metrikleri (CPU/Bellek/Sıcaklık/Fan), 1 sn'de bir.
@MainActor
@Observable
final class PanelMetrics {
    private let cpuSampler = CPUUsageSampler()
    private let smc = SMCReader()

    var cpu: Double = 0
    var memUsed: Int64 = 0
    var memFraction: Double = 0
    var temp: Double?
    var fanInfo: FanInfo?
    var fan: Double? { fanInfo?.current }

    // Fan kontrolü (yalnız M1/M2)
    let fanControlSupported = SystemMetrics.fanControlSupported
    var fanTarget: Double = 2500
    var fanBusy = false
    var fanError: String?

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        _ = cpuSampler.sample()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func stop() { task?.cancel(); task = nil }

    private func refresh() {
        cpu = cpuSampler.sample().total
        let m = SystemMetrics.memory()
        memUsed = m.used; memFraction = m.usedFraction
        temp = smc?.cpuTemperature()
        fanInfo = smc?.fan()
    }

    func applyManualFan() async {
        fanBusy = true; fanError = nil
        do { try FanController.setManual(rpm: Int(fanTarget)) }
        catch { fanError = error.localizedDescription }
        fanBusy = false
    }
    func setAutoFan() async {
        fanBusy = true; fanError = nil
        do { try FanController.setAuto() }
        catch { fanError = error.localizedDescription }
        fanBusy = false
    }
}

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
                try? await Task.sleep(for: .seconds(1))   // ucuz statfs sorgusu; sistemi yormaz
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

enum PanelTab: String, CaseIterable, Identifiable {
    case cleaning, system, fan
    var id: String { rawValue }
    @MainActor var title: String {
        switch self { case .cleaning: L("Temizlik", "Cleanup"); case .system: L("Sistem", "System"); case .fan: "Fan" }
    }
}

/// Menü çubuğundan açılan tek parça Liquid Glass panel.
/// Barındıran NSPanel tam şeffaf; bu kart tek gerçek cam yüzeydir.
struct MenuPanelView: View {
    let model: AppViewModel
    var onOpenMain: () -> Void = {}
    var onSize: (CGSize) -> Void = { _ in }

    @State private var disk = DiskMonitor()
    @State private var sys = PanelMetrics()
    @State private var tab: PanelTab = .cleaning
    @Namespace private var tabNS

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            header

            tabBar

            Group {
                switch tab {
                case .cleaning: cleaningTab
                case .system: systemTab
                case .fan: fanTab
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .id(tab)
            .transition(.opacity)

            Divider().opacity(0.3)
            footer
        }
        .padding(DS.Spacing.l)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(10)
        .background(
            GeometryReader { p in
                Color.clear
                    .onAppear { onSize(p.size) }
                    .onChange(of: p.size) { _, s in onSize(s) }
            }
        )
        .task { disk.start(); sys.start() }
        .onDisappear { disk.stop(); sys.stop() }
    }

    // MARK: - Sekme barı (ortalı, kutusuz, animasyonlu mavi alt çizgi)

    private var tabBar: some View {
        HStack(spacing: DS.Spacing.l) {
            ForEach(PanelTab.allCases) { t in
                VStack(spacing: 5) {
                    Text(t.title)
                        .font(.iCallout.weight(tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? DS.Palette.accent : Color.secondary)
                    ZStack {
                        Capsule().fill(.clear).frame(height: 2.5)
                        if tab == t {
                            Capsule().fill(DS.Palette.accent).frame(height: 2.5)
                                .matchedGeometryEffect(id: "tabUnderline", in: tabNS)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { tab = t }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Sekmeler

    private var cleaningTab: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            diskMetrics
            VStack(spacing: 2) {
                row(L("Hızlı Tarama", "Quick Scan"), "magnifyingglass") {
                    model.selectedSection = .smartScan; onOpenMain(); Task { await model.scan() }
                }
                row(L("Güvenlik Taraması", "Security Scan"), "shield.lefthalf.filled") {
                    model.selectedSection = .security; onOpenMain()
                }
                row(L("Disk Haritası", "Disk Map"), "chart.pie") {
                    model.selectedSection = .spaceLens; onOpenMain()
                }
                row(L("Uygulama Kaldırıcı", "App Uninstaller"), "trash.square") {
                    model.selectedSection = .uninstaller; onOpenMain()
                }
            }
        }
    }

    private var systemTab: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            meterRow(L("İşlemci", "Processor"), "cpu", "%\(Int((sys.cpu * 100).rounded()))",
                     fraction: sys.cpu, tint: DS.Palette.accent, valueColor: DS.Palette.accent)
            meterRow(L("Bellek", "Memory"), "memorychip", sys.memUsed.formattedBytes,
                     fraction: sys.memFraction,
                     tint: sys.memFraction > 0.9 ? DS.Palette.danger : DS.Palette.safe, valueColor: .primary)
            meterRow(L("Sıcaklık", "Temperature"), "thermometer.medium", sys.temp.map { "\(Int($0.rounded()))°" } ?? "—",
                     fraction: (sys.temp ?? 0) / 100, tint: tempColor(sys.temp), valueColor: tempColor(sys.temp))
            meterRow("Fan", "fanblades", sys.fan.map { "\(Int($0)) RPM" } ?? "—",
                     fraction: sys.fanInfo.map { $0.max > 0 ? $0.current / $0.max : 0 } ?? 0,
                     tint: DS.Palette.accent, valueColor: .primary)

            VStack(spacing: 2) {
                row(L("Sistem Monitörü'nü Aç", "Open System Monitor"), "gauge.with.dots.needle.67percent") {
                    model.selectedSection = .monitor; onOpenMain()
                }
                row(L("Bakım", "Maintenance"), "wrench.and.screwdriver") {
                    model.selectedSection = .maintenance; onOpenMain()
                }
            }
        }
    }

    /// Etiket + değer + ilerleme çubuğu (tüm sistem metrikleri için tutarlı).
    private func meterRow(_ title: String, _ symbol: String, _ value: String,
                          fraction: Double, tint: Color, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label(title, systemImage: symbol).font(.iCaption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.iCallout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(valueColor)
                    .contentTransition(.numericText())
            }
            ProgressView(value: min(max(fraction, 0), 1)).tint(tint)
                .animation(.easeInOut(duration: 0.45), value: fraction)
        }
    }

    private var fanTab: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            if let fan = sys.fanInfo {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(fan.current))").font(.dsDisplay(34)).monospacedDigit().contentTransition(.numericText())
                    Text("RPM").font(.iCallout).foregroundStyle(.secondary)
                    Spacer()
                }

                if sys.fanControlSupported, fan.max > fan.min {
                    Text(L("Manuel hız (yönetici parolası ister)", "Manual speed (asks for admin password)")).font(.iCaption2).foregroundStyle(.secondary)
                    HStack(spacing: DS.Spacing.s) {
                        Text("\(Int(fan.min))").font(.iCaption2).foregroundStyle(.tertiary)
                        Slider(value: Binding(get: { sys.fanTarget }, set: { sys.fanTarget = $0 }), in: fan.min...fan.max, step: 50)
                        Text("\(Int(fan.max))").font(.iCaption2).foregroundStyle(.tertiary)
                    }
                    Text("\(Int(sys.fanTarget)) RPM").font(.iCallout.weight(.semibold).monospacedDigit()).contentTransition(.numericText())
                    HStack(spacing: DS.Spacing.s) {
                        Button { Task { await sys.applyManualFan() } } label: {
                            Label(L("Uygula", "Apply"), systemImage: "wind")
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small).disabled(sys.fanBusy)
                        Button(L("Normale Dön", "Reset to Auto")) { Task { await sys.setAutoFan() } }
                            .buttonStyle(.bordered).controlSize(.small).disabled(sys.fanBusy)
                        if sys.fanBusy { ProgressView().controlSize(.small) }
                        Spacer()
                    }
                    if let e = sys.fanError {
                        Text(e).font(.iCaption2).foregroundStyle(DS.Palette.danger).lineLimit(2)
                    } else {
                        Text(L("Manuel modda fan otomatik hızlanmaz.", "In manual mode the fan won't auto-speed up.")).font(.iCaption2).foregroundStyle(.tertiary)
                    }
                } else if !sys.fanControlSupported {
                    Text(L("Fan kontrolü bu çipte (M3+) Apple tarafından kısıtlı — yalnızca okuma.", "Fan control is restricted by Apple on this chip (M3+) — read-only."))
                        .font(.iCaption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(L("Bu Mac'te fan yok veya okunamıyor (ör. MacBook Air).", "This Mac has no fan or it can't be read (e.g. MacBook Air)."))
                    .font(.iCallout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: "sparkles")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("PureGlass").font(.iHeadline)
                Text(L("Hızlı temizlik", "Quick cleanup")).font(.iCaption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Canlı disk metrikleri

    private var diskMetrics: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack {
                Label(L("Depolama", "Storage"), systemImage: "internaldrive")
                    .font(.iCaption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    openStorageSettings()
                } label: {
                    Label(L("Sistem Ayarları", "System Settings"), systemImage: "gearshape")
                        .font(.iCaption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help(L("Sistem Ayarları → Depolama'yı aç", "Open System Settings → Storage"))
            }

            ProgressView(value: disk.usedFraction)
                .tint(disk.usedFraction > 0.9 ? DS.Palette.danger
                      : disk.usedFraction > 0.75 ? DS.Palette.caution : DS.Palette.accent)

            HStack(spacing: DS.Spacing.m) {
                metric(L("Boş", "Free"), disk.free.formattedBytes, DS.Palette.safe)
                metric(L("Kullanılan", "Used"), disk.used.formattedBytes, .primary)
                if disk.purgeable > 0 {
                    metric(L("Boşaltılabilir", "Purgeable"), disk.purgeable.formattedBytes, DS.Palette.accent)
                }
            }
            Text(L("Toplam \(disk.total.formattedBytes) • her saniye güncellenir", "Total \(disk.total.formattedBytes) • updates every second"))
                .font(.iCaption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Canlı sistem metrikleri (CPU/Bellek/Sıcaklık/Fan)

    private func tempColor(_ t: Double?) -> Color {
        guard let t else { return .secondary }
        return t < 55 ? DS.Palette.safe : t < 75 ? DS.Palette.caution : DS.Palette.danger
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.iCaption2).foregroundStyle(.secondary)
            Text(value).font(.iCallout.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.65)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L("Çık", "Quit")) { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.iCaption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: symbol).frame(width: 20, alignment: .leading)
                Text(title)
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, DS.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
        .padding(.horizontal, -DS.Spacing.s)   // içerik kenarla aynı hizada; vurgu hafif taşar
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
