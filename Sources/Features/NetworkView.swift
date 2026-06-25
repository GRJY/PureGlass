import SwiftUI
import Observation
import AppKit
import PureGlassKit

struct NetPoint: Identifiable, Equatable {
    let id: Int
    let latency: Double?   // ms, nil = paket kaybı
}

@MainActor
@Observable
final class NetworkViewModel {
    var status = NetworkInfo.current()
    var wifi: WiFiStatus?
    var history: [NetPoint] = []
    private var sampleIndex = 0

    var latency: Double?
    var jitter: Double?
    var loss: Double = 0

    var speedRunning = false
    var speed: SpeedResult?

    var dnsBusy = false
    var dnsError: String?

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.status = NetworkInfo.current()
                self.wifi = WiFiInfo.current()
                let ms = await Task.detached { PingMonitor.ping("1.1.1.1", timeoutMs: 1500) }.value
                if Task.isCancelled { return }
                self.record(ms)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func record(_ ms: Double?) {
        latency = ms
        history.append(NetPoint(id: sampleIndex, latency: ms))
        sampleIndex += 1
        if history.count > 60 { history.removeFirst() }
        let recent = history.suffix(20)
        let oks = recent.compactMap(\.latency)
        loss = recent.isEmpty ? 0 : Double(recent.count - oks.count) / Double(recent.count)
        if oks.count > 1 {
            let mean = oks.reduce(0, +) / Double(oks.count)
            let variance = oks.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(oks.count)
            jitter = variance.squareRoot()
        } else { jitter = nil }
    }

    func runSpeedTest() async {
        speedRunning = true; speed = nil
        let result = await Task.detached { SpeedTest.run() }.value
        speed = result
        speedRunning = false
    }

    func applyDNS(_ servers: [String]) async {
        dnsBusy = true; dnsError = nil
        guard let service = DNSManager.serviceName(for: status.interface) else {
            dnsError = L("Ağ servisi bulunamadı.", "Network service not found."); dnsBusy = false; return
        }
        guard let cmd = DNSManager.setDNSCommand(service: service, servers: servers) else {
            dnsError = L("Geçersiz DNS adresi.", "Invalid DNS address."); dnsBusy = false; return
        }
        do {
            try AdminShell.run(cmd + "; " + DNSManager.flushDNSCommand)
            status = NetworkInfo.current()
        } catch { dnsError = error.localizedDescription }
        dnsBusy = false
    }

    func renewDHCP() async {
        dnsBusy = true; dnsError = nil
        guard let service = DNSManager.serviceName(for: status.interface) else { dnsBusy = false; return }
        do { try AdminShell.run(DNSManager.renewDHCPCommand(service: service)); status = NetworkInfo.current() }
        catch { dnsError = error.localizedDescription }
        dnsBusy = false
    }
}

struct DNSChoice: Identifiable {
    let id: String
    let name: String
    let servers: [String]
}

struct NetworkView: View {
    @State private var model = NetworkViewModel()

    private let cols = [
        GridItem(.flexible(), spacing: DS.Spacing.m, alignment: .top),
        GridItem(.flexible(), spacing: DS.Spacing.m, alignment: .top)
    ]

    private var dnsChoices: [DNSChoice] {
        [
            .init(id: "auto", name: L("Otomatik", "Automatic"), servers: []),
            .init(id: "cloudflare", name: "Cloudflare", servers: ["1.1.1.1", "1.0.0.1"]),
            .init(id: "google", name: "Google", servers: ["8.8.8.8", "8.8.4.4"]),
            .init(id: "quad9", name: "Quad9", servers: ["9.9.9.9", "149.112.112.112"]),
            .init(id: "opendns", name: "OpenDNS", servers: ["208.67.222.222", "208.67.220.220"])
        ]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: DS.Spacing.m) {
                connectionCard
                if model.wifi != nil { wifiCard }
                stabilityCard
                speedCard
                dnsCard
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: Bağlantı

    private var connectionCard: some View {
        GlassCard(fill: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                header(L("Bağlantı", "Connection"), "network", DS.Palette.accent)
                infoRow(L("Durum", "Status"),
                        model.status.isOnline ? L("Bağlı", "Online") : L("Bağlı değil", "Offline"),
                        model.status.isOnline ? DS.Palette.safe : DS.Palette.danger)
                infoRow(L("Tür", "Type"), model.status.isWiFi ? "Wi-Fi" : L("Kablolu", "Ethernet"), .primary)
                infoRow(L("Arayüz", "Interface"), model.status.interface, .primary)
                infoRow("IP", model.status.ipAddress ?? "—", .primary)
                infoRow(L("Ağ geçidi", "Gateway"), model.status.gateway ?? "—", .primary)
                infoRow("DNS", model.status.dnsServers.first ?? L("Otomatik", "Automatic"), .primary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Wi-Fi

    @ViewBuilder private var wifiCard: some View {
        if let w = model.wifi {
            GlassCard(fill: true) {
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    header(L("Wi-Fi Sinyali", "Wi-Fi Signal"), "wifi", DS.Palette.accent)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(w.quality, format: .percent.precision(.fractionLength(0)))
                            .font(.dsDisplay(34)).monospacedDigit()
                        Text(L("kalite", "quality")).font(.iCaption).foregroundStyle(.secondary)
                        Spacer()
                        signalBars(w.bars)
                    }
                    ProgressView(value: w.quality).tint(qualityColor(w.quality))
                    infoRow(L("Sinyal", "Signal"), "\(w.rssi) dBm", .primary)
                    infoRow(L("Link hızı", "Link rate"), "\(Int(w.txRate)) Mbps", .primary)
                    infoRow(L("Kanal", "Channel"), "\(w.channel)", .primary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func signalBars(_ n: Int) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < n ? DS.Palette.accent : Color.primary.opacity(0.15))
                    .frame(width: 5, height: CGFloat(8 + i * 5))
            }
        }
    }

    // MARK: Kararlılık (canlı)

    private var stabilityCard: some View {
        GlassCard(fill: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                header(L("Kararlılık", "Stability"), "waveform.path.ecg", stabilityColor)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.latency.map { "\(Int($0))" } ?? "—")
                        .font(.dsDisplay(34)).monospacedDigit().contentTransition(.numericText())
                    Text("ms").font(.iCallout).foregroundStyle(.secondary)
                    Spacer()
                }
                latencyChart
                HStack(spacing: DS.Spacing.l) {
                    legend(L("Gecikme", "Latency"), model.latency.map { "\(Int($0)) ms" } ?? "—", stabilityColor)
                    legend(L("Jitter", "Jitter"), model.jitter.map { "\(Int($0)) ms" } ?? "—", DS.Palette.accent)
                    legend(L("Kayıp", "Loss"), "\(Int(model.loss * 100))%", model.loss > 0.05 ? DS.Palette.danger : DS.Palette.safe)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var latencyChart: some View {
        Canvas { ctx, size in
            let pts = model.history
            guard pts.count > 1 else { return }
            let scale = max(80.0, (pts.compactMap(\.latency).max() ?? 80) * 1.2)
            let n = pts.count
            func pt(_ i: Int, _ v: Double) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(n - 1),
                        y: size.height * (1 - CGFloat(min(v / scale, 1))))
            }
            var line = Path(); var started = false
            for i in 0..<n {
                guard let v = pts[i].latency else { continue }
                let p = pt(i, v)
                if !started { line.move(to: p); started = true } else { line.addLine(to: p) }
            }
            if started {
                var fill = line
                fill.addLine(to: CGPoint(x: size.width, y: size.height))
                fill.addLine(to: CGPoint(x: 0, y: size.height))
                fill.closeSubpath()
                ctx.fill(fill, with: .linearGradient(
                    Gradient(colors: [stabilityColor.opacity(0.35), stabilityColor.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
                ctx.stroke(line, with: .color(stabilityColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 56)
    }

    // MARK: Hız testi

    private var speedCard: some View {
        GlassCard(fill: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                header(L("Hız Testi", "Speed Test"), "speedometer", DS.Palette.accent)
                if let s = model.speed {
                    HStack(spacing: DS.Spacing.l) {
                        speedStat(L("İndirme", "Download"), s.downloadMbps, "arrow.down")
                        speedStat(L("Yükleme", "Upload"), s.uploadMbps, "arrow.up")
                    }
                    infoRow(L("Tepkisellik", "Responsiveness"), "\(s.responsiveness) RPM", .secondary)
                } else {
                    Text(L("İndirme/yükleme hızını ve tepkiselliği Apple'ın networkQuality aracıyla ölçer.",
                          "Measures download/upload speed and responsiveness with Apple's networkQuality."))
                        .font(.iCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Task { await model.runSpeedTest() }
                } label: {
                    if model.speedRunning {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L("Ölçülüyor… (~20 sn)", "Testing… (~20s)")) }
                    } else {
                        Label(L("Testi Başlat", "Run Test"), systemImage: "play.fill")
                    }
                }
                .buttonStyle(.glassProminent).tint(.accentColor).disabled(model.speedRunning)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func speedStat(_ label: String, _ mbps: Double, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(label, systemImage: icon).font(.iCaption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(mbps, format: .number.precision(.fractionLength(mbps < 100 ? 1 : 0)))
                    .font(.dsDisplay(26)).monospacedDigit()
                Text("Mbps").font(.iCaption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: DNS

    private var dnsCard: some View {
        GlassCard(fill: true) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                header("DNS", "globe", DS.Palette.accent)
                Text(L("Hızlı ve gizlilik dostu bir DNS seç (yönetici parolası ister).",
                      "Pick a fast, privacy-friendly DNS (asks for admin password)."))
                    .font(.iCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                FlowDNS(choices: dnsChoices, current: model.status.dnsServers, busy: model.dnsBusy) { servers in
                    Task { await model.applyDNS(servers) }
                }
                HStack(spacing: DS.Spacing.s) {
                    Button { Task { await model.renewDHCP() } } label: {
                        Label(L("IP Yenile", "Renew IP"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass).controlSize(.small).disabled(model.dnsBusy)
                    if model.dnsBusy { ProgressView().controlSize(.small) }
                    Spacer()
                }
                if let e = model.dnsError {
                    Text(e).font(.iCaption2).foregroundStyle(DS.Palette.danger).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Yardımcılar

    private func header(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label(title, systemImage: symbol).font(.dsTitle).foregroundStyle(DS.Palette.accent)
    }

    private func infoRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.iCallout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.iCallout.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
    }

    private func legend(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.iCaption2).foregroundStyle(.secondary)
            Text(value).font(.iCaption.weight(.semibold).monospacedDigit())
        }
    }

    private var stabilityColor: Color {
        guard let l = model.latency else { return DS.Palette.danger }
        if model.loss > 0.05 { return DS.Palette.danger }
        return l < 50 ? DS.Palette.safe : l < 120 ? DS.Palette.caution : DS.Palette.danger
    }
    private func qualityColor(_ q: Double) -> Color {
        q > 0.6 ? DS.Palette.safe : q > 0.3 ? DS.Palette.caution : DS.Palette.danger
    }
}

/// DNS seçeneklerini saran, aktif olanı işaretleyen buton akışı.
private struct FlowDNS: View {
    let choices: [DNSChoice]
    let current: [String]
    let busy: Bool
    let apply: ([String]) -> Void

    private func isActive(_ c: DNSChoice) -> Bool {
        if c.servers.isEmpty { return current.isEmpty }
        return Set(c.servers) == Set(current)
    }

    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 92), spacing: 6)]
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(choices) { c in
                if isActive(c) {
                    Button { apply(c.servers) } label: { label(c) }
                        .buttonStyle(.glassProminent).tint(.accentColor).disabled(busy)
                } else {
                    Button { apply(c.servers) } label: { label(c) }
                        .buttonStyle(.glass).disabled(busy)
                }
            }
        }
    }

    private func label(_ c: DNSChoice) -> some View {
        Text(c.name).font(.iCaption.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 1)
    }
}
