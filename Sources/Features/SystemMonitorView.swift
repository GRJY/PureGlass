import SwiftUI
import Observation
import AppKit
import PureGlassKit

/// CPU geçmiş grafiği için tek nokta.
struct CPUPoint: Identifiable, Equatable {
    let id: Int
    let value: Double
}

@MainActor
@Observable
final class SystemMonitorViewModel {
    private let cpuSampler = CPUUsageSampler()
    private let smc = SMCReader()
    private var task: Task<Void, Never>?

    var cpuTotal: Double = 0
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuPerCore: [Double] = []
    var cpuHistory: [CPUPoint] = []
    private var cpuSampleIndex = 0
    var memory = SystemMetrics.memory()
    var thermalState: ProcessInfo.ThermalState = .nominal
    var cpuTemp: Double?
    var peakTemp: Double?
    var batteryTemp: Double?
    var fan: FanInfo?
    var hasSMC: Bool { smc != nil }

    // Fan kontrolü (yalnızca M1/M2)
    let fanControlSupported = SystemMetrics.fanControlSupported
    var fanManual = false
    var fanTarget: Double = 2500
    var fanBusy = false
    var fanError: String?

    func applyManualFan() async {
        fanBusy = true; fanError = nil
        do { try FanController.setManual(rpm: Int(fanTarget)); fanManual = true }
        catch { fanError = error.localizedDescription }
        fanBusy = false
    }

    func setAutoFan() async {
        fanBusy = true; fanError = nil
        do { try FanController.setAuto(); fanManual = false }
        catch { fanError = error.localizedDescription }
        fanBusy = false
    }

    func start() {
        guard task == nil else { return }
        _ = cpuSampler.sample()   // taban örneği
        task = Task { [weak self] in
            var n = 0
            while !Task.isCancelled {
                self?.sampleCPU()                       // her 0.5 sn → akıcı grafik
                if n % 2 == 0 { self?.refreshSensors() } // her 1 sn → sıcaklık/fan stabil
                n += 1
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func sampleCPU() {
        let u = cpuSampler.sample()
        cpuTotal = u.total
        cpuUser = u.user
        cpuSystem = u.system
        cpuPerCore = u.perCore
        cpuHistory.append(CPUPoint(id: cpuSampleIndex, value: u.total))
        cpuSampleIndex += 1
        if cpuHistory.count > 60 { cpuHistory.removeFirst() }
    }

    private func refreshSensors() {
        memory = SystemMetrics.memory()
        thermalState = ProcessInfo.processInfo.thermalState
        cpuTemp = smc?.cpuTemperature()
        peakTemp = smc?.peakTemperature()
        batteryTemp = smc?.batteryTemperature()
        fan = smc?.fan()
    }
}

struct SystemMonitorView: View {
    @State private var model = SystemMonitorViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.m) {
                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    cpuCard
                    memoryCard
                }
                HStack(alignment: .top, spacing: DS.Spacing.m) {
                    thermalCard
                    fanCard
                }
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: - CPU

    private var cpuCard: some View {
        GlassCard(fill: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                cardHeader(L("İşlemci (CPU)", "Processor (CPU)"), "cpu", DS.Palette.accent)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.cpuTotal, format: .percent.precision(.fractionLength(0)))
                        .font(.dsDisplay(40)).monospacedDigit().contentTransition(.numericText())
                    Text(L("kullanım", "usage")).font(.iCaption).foregroundStyle(.secondary)
                    Spacer()
                    Text(L("\(model.cpuPerCore.count) çekirdek", "\(model.cpuPerCore.count) cores")).font(.iCaption2).foregroundStyle(.tertiary)
                }

                cpuHistoryChart

                HStack(spacing: DS.Spacing.l) {
                    cpuLegend(L("Sistem", "System"), model.cpuSystem, DS.Palette.danger)
                    cpuLegend(L("Kullanıcı", "User"), model.cpuUser, DS.Palette.accent)
                    cpuLegend(L("Boş", "Free"), 1 - model.cpuTotal, .secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Canvas tabanlı smooth CPU geçmiş grafiği. Swift Charts'ın her veri değişiminde
    // tüm görünümü yeniden kurup yanıp sönmesini önler; Canvas yalnızca yeniden çizer.
    private var cpuHistoryChart: some View {
        Canvas { ctx, size in
            let pts = model.cpuHistory
            guard pts.count > 1 else { return }
            let n = pts.count
            func cgPoint(_ i: Int) -> CGPoint {
                let x = size.width * CGFloat(i) / CGFloat(n - 1)
                let y = size.height * (1 - CGFloat(min(max(pts[i].value, 0), 1)))
                return CGPoint(x: x, y: y)
            }
            // Catmull-Rom benzeri yumuşatma: ardışık noktalar arası quad eğriler.
            var line = Path()
            line.move(to: cgPoint(0))
            for i in 0..<(n - 1) {
                let p0 = cgPoint(i), p1 = cgPoint(i + 1)
                let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
                line.addQuadCurve(to: mid, control: p0)
                line.addQuadCurve(to: p1, control: mid)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [DS.Palette.accent.opacity(0.40), DS.Palette.accent.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(DS.Palette.accent),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 64)
    }

    private func cpuLegend(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.iCaption2).foregroundStyle(.secondary)
            Text(value, format: .percent.precision(.fractionLength(0)))
                .font(.iCaption.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
    }

    // MARK: - Bellek

    private var memoryCard: some View {
        GlassCard(fill: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                cardHeader(L("Bellek (RAM)", "Memory (RAM)"), "memorychip", DS.Palette.safe)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.memory.used.formattedBytes).font(.dsDisplay(30)).monospacedDigit()
                    Text("/ \(model.memory.total.formattedBytes)").font(.iCallout).foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(pressureColor).frame(width: 8, height: 8)
                        Text(model.memory.pressureTitle).font(.iCaption.weight(.semibold)).foregroundStyle(pressureColor)
                    }
                }
                ProgressView(value: model.memory.usedFraction)
                    .tint(model.memory.usedFraction > 0.9 ? DS.Palette.danger : DS.Palette.safe)
                    .animation(.easeInOut(duration: 0.4), value: model.memory.usedFraction)
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                } label: {
                    Label(L("Activity Monitor'da aç", "Open in Activity Monitor"), systemImage: "arrow.up.forward.app").font(.iCaption)
                }
                .buttonStyle(.link).foregroundStyle(DS.Palette.accent)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Termal

    private var thermalCard: some View {
        GlassCard(fill: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                cardHeader(L("Sıcaklık & Termal", "Temperature & Thermal"), "thermometer.medium", thermalColor)
                HStack {
                    Text(L("Termal durum", "Thermal state")).font(.iCallout).foregroundStyle(.secondary)
                    Spacer()
                    Text(thermalTitle).font(.iHeadline).foregroundStyle(thermalColor)
                }
                Divider().opacity(0.2)
                tempRow(L("CPU bölgesi", "CPU area"), model.cpuTemp)
                tempRow(L("En sıcak sensör", "Hottest sensor"), model.peakTemp)
                tempRow(L("Batarya", "Battery"), model.batteryTemp)
                if !model.hasSMC {
                    Text(L("Sıcaklık sensörlerine erişilemiyor.", "Temperature sensors are unavailable.")).font(.iCaption2).foregroundStyle(.tertiary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tempRow(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Text(label).font(.iCallout)
            Spacer()
            if let v = value {
                Circle().fill(tempColor(v)).frame(width: 9, height: 9)
                    .animation(DS.Anim.smooth, value: tempColor(v))
                Text("\(Int(v.rounded()))°C")
                    .font(.iCallout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tempColor(v))
                    .contentTransition(.numericText())
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Fan

    private var fanCard: some View {
        GlassCard(fill: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                cardHeader("Fan", "fanblades", DS.Palette.accent)
                if let fan = model.fan {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(fan.current))").font(.dsDisplay(34)).monospacedDigit().contentTransition(.numericText())
                        Text("RPM").font(.iCallout).foregroundStyle(.secondary)
                        Spacer()
                    }
                    fanControls(fan)
                } else {
                    Text(L("Bu Mac'te fan yok veya okunamıyor (ör. MacBook Air).", "This Mac has no fan or it can't be read (e.g. MacBook Air)."))
                        .font(.iCallout).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func fanControls(_ fan: FanInfo) -> some View {
        if model.fanControlSupported, fan.max > fan.min {
            Text(L("Manuel hız (yönetici parolası ister)", "Manual speed (asks for admin password)")).font(.iCaption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: DS.Spacing.s) {
                Text("\(Int(fan.min))").font(.iCaption2).foregroundStyle(.tertiary)
                Slider(value: Binding(get: { model.fanTarget }, set: { model.fanTarget = $0 }),
                       in: fan.min...fan.max, step: 50)
                Text("\(Int(fan.max))").font(.iCaption2).foregroundStyle(.tertiary)
            }
            Text("\(Int(model.fanTarget)) RPM").font(.iCallout.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            HStack(spacing: DS.Spacing.s) {
                Button { Task { await model.applyManualFan() } } label: {
                    Label(L("Uygula", "Apply"), systemImage: "wind").padding(.horizontal, 4)
                }
                .buttonStyle(.glassProminent).tint(.accentColor).disabled(model.fanBusy)
                Button(L("Normale Dön", "Reset to Auto")) { Task { await model.setAutoFan() } }
                    .buttonStyle(.glass).disabled(model.fanBusy)
                if model.fanBusy { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let e = model.fanError {
                Text(e).font(.iCaption2).foregroundStyle(DS.Palette.danger)
            } else {
                Text(L("Manuel modda fan otomatik hızlanmaz.", "In manual mode the fan won't auto-speed up.")).font(.iCaption2).foregroundStyle(.tertiary)
            }
        } else if !model.fanControlSupported {
            Text(L("Fan kontrolü bu çipte (M3+) Apple tarafından kısıtlı — yalnızca okuma.", "Fan control is restricted by Apple on this chip (M3+) — read-only."))
                .font(.iCaption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Yardımcılar

    private func cardHeader(_ title: String, _ symbol: String, _ color: Color = .clear) -> some View {
        // Tüm kart başlıkları tek tip MAVİ.
        Label(title, systemImage: symbol).font(.dsTitle).foregroundStyle(DS.Palette.accent)
    }

    private var thermalTitle: String {
        switch model.thermalState {
        case .nominal: "Normal"; case .fair: "Orta"; case .serious: L("Yüksek", "High"); case .critical: "Kritik"
        @unknown default: "—"
        }
    }
    private var thermalColor: Color {
        switch model.thermalState {
        case .nominal: DS.Palette.safe; case .fair: DS.Palette.accent
        case .serious: DS.Palette.caution; case .critical: DS.Palette.danger
        @unknown default: .secondary
        }
    }
    private var pressureColor: Color {
        switch model.memory.pressureLevel { case 4: DS.Palette.danger; case 2: DS.Palette.caution; default: DS.Palette.safe }
    }
    private func tempColor(_ t: Double) -> Color {
        switch t { case ..<55: DS.Palette.safe; case ..<75: DS.Palette.caution; default: DS.Palette.danger }
    }
}
