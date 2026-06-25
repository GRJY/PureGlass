import SwiftUI
import Observation
import AppKit
import Charts
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
                cardHeader("İşlemci (CPU)", "cpu", DS.Palette.accent)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.cpuTotal, format: .percent.precision(.fractionLength(0)))
                        .font(.dsDisplay(40)).monospacedDigit().contentTransition(.numericText())
                    Text("kullanım").font(.iCaption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.cpuPerCore.count) çekirdek").font(.iCaption2).foregroundStyle(.tertiary)
                }

                cpuHistoryChart

                HStack(spacing: DS.Spacing.l) {
                    cpuLegend("Sistem", model.cpuSystem, DS.Palette.danger)
                    cpuLegend("Kullanıcı", model.cpuUser, DS.Palette.accent)
                    cpuLegend("Boş", 1 - model.cpuTotal, .secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cpuHistoryChart: some View {
        Chart(model.cpuHistory) { p in
            AreaMark(x: .value("t", p.id), y: .value("cpu", p.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.linearGradient(
                    colors: [DS.Palette.accent.opacity(0.45), DS.Palette.accent.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("t", p.id), y: .value("cpu", p.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(DS.Palette.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXScale(domain: (model.cpuHistory.first?.id ?? 0)...(max((model.cpuHistory.first?.id ?? 0) + 1, model.cpuHistory.last?.id ?? 1)))
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 64)
        .animation(.linear(duration: 0.5), value: model.cpuHistory)
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
                cardHeader("Bellek (RAM)", "memorychip", DS.Palette.safe)
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
                    Label("Activity Monitor'da aç", systemImage: "arrow.up.forward.app").font(.iCaption)
                }
                .buttonStyle(.link).foregroundStyle(DS.Palette.accent)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Termal

    private var thermalCard: some View {
        GlassCard(fill: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                cardHeader("Sıcaklık & Termal", "thermometer.medium", thermalColor)
                HStack {
                    Text("Termal durum").font(.iCallout).foregroundStyle(.secondary)
                    Spacer()
                    Text(thermalTitle).font(.iHeadline).foregroundStyle(thermalColor)
                }
                Divider().opacity(0.2)
                tempRow("CPU bölgesi", model.cpuTemp)
                tempRow("En sıcak sensör", model.peakTemp)
                tempRow("Batarya", model.batteryTemp)
                if !model.hasSMC {
                    Text("Sıcaklık sensörlerine erişilemiyor.").font(.iCaption2).foregroundStyle(.tertiary)
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
                    Text("Bu Mac'te fan yok veya okunamıyor (ör. MacBook Air).")
                        .font(.iCallout).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func fanControls(_ fan: FanInfo) -> some View {
        if model.fanControlSupported, fan.max > fan.min {
            Text("Manuel hız (yönetici parolası ister)").font(.iCaption.weight(.medium)).foregroundStyle(.secondary)
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
                    Label("Uygula", systemImage: "wind").padding(.horizontal, 4)
                }
                .buttonStyle(.glassProminent).tint(.accentColor).disabled(model.fanBusy)
                Button("Normale Dön") { Task { await model.setAutoFan() } }
                    .buttonStyle(.glass).disabled(model.fanBusy)
                if model.fanBusy { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let e = model.fanError {
                Text(e).font(.iCaption2).foregroundStyle(DS.Palette.danger)
            } else {
                Text("Manuel modda fan otomatik hızlanmaz.").font(.iCaption2).foregroundStyle(.tertiary)
            }
        } else if !model.fanControlSupported {
            Text("Fan kontrolü bu çipte (M3+) Apple tarafından kısıtlı — yalnızca okuma.")
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
        case .nominal: "Normal"; case .fair: "Orta"; case .serious: "Yüksek"; case .critical: "Kritik"
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
