import SwiftUI
import Observation
import PureGlassKit

@MainActor
@Observable
final class SystemMonitorViewModel {
    private let cpuSampler = CPUUsageSampler()
    private let smc = SMCReader()
    private var task: Task<Void, Never>?

    var cpuTotal: Double = 0
    var cpuPerCore: [Double] = []
    var memory = SystemMetrics.memory()
    var thermalState: ProcessInfo.ThermalState = .nominal
    var cpuTemp: Double?
    var peakTemp: Double?
    var batteryTemp: Double?
    var fan: FanInfo?
    var hasSMC: Bool { smc != nil }

    func start() {
        guard task == nil else { return }
        _ = cpuSampler.sample()   // taban örneği
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func refresh() {
        let (t, pc) = cpuSampler.sample()
        cpuTotal = t
        cpuPerCore = pc
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

    private let cols = [GridItem(.adaptive(minimum: 280), spacing: DS.Spacing.m)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: DS.Spacing.m) {
                cpuCard
                memoryCard
                thermalCard
                fanCard
            }
            .padding(DS.Spacing.l)
        }
        .navigationTitle("Sistem Monitörü")
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: - CPU

    private var cpuCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                cardHeader("İşlemci (CPU)", "cpu", DS.Palette.accent)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.cpuTotal, format: .percent.precision(.fractionLength(0)))
                        .font(.dsDisplay(40)).monospacedDigit().contentTransition(.numericText())
                    Text("kullanım").font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: model.cpuTotal).tint(DS.Palette.accent)
                if !model.cpuPerCore.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(model.cpuPerCore.enumerated()), id: \.offset) { _, v in
                            GeometryReader { geo in
                                VStack {
                                    Spacer(minLength: 0)
                                    Capsule().fill(DS.Palette.accent.gradient)
                                        .frame(height: max(2, geo.size.height * v))
                                }
                            }
                            .frame(height: 36)
                        }
                    }
                    Text("\(model.cpuPerCore.count) çekirdek").font(.caption2).foregroundStyle(.tertiary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Bellek

    private var memoryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                cardHeader("Bellek (RAM)", "memorychip", DS.Palette.safe)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.memory.used.formattedBytes).font(.dsDisplay(30)).monospacedDigit()
                    Text("/ \(model.memory.total.formattedBytes)").font(.callout).foregroundStyle(.secondary)
                }
                ProgressView(value: model.memory.usedFraction)
                    .tint(model.memory.usedFraction > 0.9 ? DS.Palette.danger : DS.Palette.safe)
                HStack {
                    Text("Bellek baskısı").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(model.memory.pressureTitle).font(.caption.weight(.semibold))
                        .foregroundStyle(pressureColor)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Termal

    private var thermalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                cardHeader("Sıcaklık & Termal", "thermometer.medium", thermalColor)
                HStack {
                    Text("Termal durum").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(thermalTitle).font(.headline).foregroundStyle(thermalColor)
                }
                Divider().opacity(0.2)
                tempRow("CPU bölgesi", model.cpuTemp)
                tempRow("En sıcak sensör", model.peakTemp)
                tempRow("Batarya", model.batteryTemp)
                if !model.hasSMC {
                    Text("Sıcaklık sensörlerine erişilemiyor.").font(.caption2).foregroundStyle(.tertiary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tempRow(_ label: String, _ value: Double?) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            if let v = value {
                Text("\(Int(v.rounded()))°C").font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tempColor(v))
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Fan

    private var fanCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                cardHeader("Fan", "fanblades", DS.Palette.accent)
                if let fan = model.fan {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(fan.current))").font(.dsDisplay(34)).monospacedDigit().contentTransition(.numericText())
                        Text("RPM").font(.callout).foregroundStyle(.secondary)
                        if fan.current == 0 { Text("(boşta)").font(.caption).foregroundStyle(.tertiary) }
                    }
                    ProgressView(value: fan.max > 0 ? fan.current / fan.max : 0).tint(DS.Palette.accent)
                    HStack {
                        Text("Min \(Int(fan.min)) · Maks \(Int(fan.max))").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(fan.auto ? "Otomatik" : "Manuel")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(fan.auto ? DS.Palette.safe : DS.Palette.caution)
                    }
                } else {
                    Text("Bu Mac'te fan yok veya okunamıyor (ör. MacBook Air).")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Yardımcılar

    private func cardHeader(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label(title, systemImage: symbol).font(.dsTitle).foregroundStyle(color)
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
