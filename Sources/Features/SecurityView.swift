import SwiftUI
import AppKit
import Observation
import PureGlassKit

@MainActor
@Observable
final class SecurityViewModel {
    private let scanner = ThreatScanner()

    var threats: [Threat] = []
    var scanning = false
    var scanned = false
    var resultMessage: String?

    func scan() async {
        scanning = true
        scanned = false
        resultMessage = nil
        threats = await scanner.scan()
        scanning = false
        scanned = true
    }

    func quarantine(_ threat: Threat) {
        guard let path = threat.path else { return }
        do {
            try FileManager.default.trashItem(at: path, resultingItemURL: nil)
            threats.removeAll { $0.id == threat.id }
            resultMessage = "\(path.lastPathComponent) karantinaya alındı (Çöp Kutusu)"
        } catch {
            resultMessage = "Karantina başarısız (yetki gerekebilir): \(error.localizedDescription)"
        }
    }

    func reveal(_ threat: Threat) {
        if let p = threat.path { NSWorkspace.shared.activateFileViewerSelecting([p]) }
    }
}

struct SecurityView: View {
    @State private var model = SecurityViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            content
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Güvenlik Taraması").font(.dsTitle)
                Spacer()
                if let msg = model.resultMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Zararlı yazılım, şüpheli kalıcı görevler ve hosts ele geçirmesi için sezgisel tarama. Bulut antivirüs değildir; tamamen lokalde çalışır.")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.m)
    }

    @ViewBuilder
    private var content: some View {
        if model.scanning {
            centered {
                ProgressView().controlSize(.large)
                Text("Tehditler taranıyor…").foregroundStyle(.secondary)
            }
        } else if !model.scanned {
            centered {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 60, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("Mac'ini zararlı yazılımlara karşı tara").font(.dsTitle)
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Taramayı Başlat", systemImage: "shield")
                        .padding(.horizontal, DS.Spacing.l).padding(.vertical, DS.Spacing.s)
                }
                .buttonStyle(.glassProminent).tint(.accentColor).controlSize(.extraLarge)
            }
        } else if model.threats.isEmpty {
            centered {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 64)).foregroundStyle(DS.Palette.safe)
                Text("Tehdit bulunamadı").font(.dsDisplay(30))
                Text("Bilinen göstergeler ve şüpheli kalıcı görevler bulunamadı.")
                    .foregroundStyle(.secondary)
                Button("Tekrar Tara") { Task { await model.scan() } }.buttonStyle(.glass)
            }
        } else {
            VStack(spacing: 0) {
                List {
                    ForEach(model.threats) { threat in
                        ThreatRow(threat: threat,
                                  onReveal: { model.reveal(threat) },
                                  onQuarantine: { model.quarantine(threat) })
                    }
                }
                .scrollContentBackground(.hidden)
                HStack {
                    Label("\(model.threats.count) bulgu", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.caution)
                    Spacer()
                    Button("Tekrar Tara") { Task { await model.scan() } }.buttonStyle(.glass)
                }
                .padding(DS.Spacing.l)
                .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.l))
                .padding(.horizontal, DS.Spacing.m).padding(.bottom, DS.Spacing.m)
            }
        }
    }

    private func centered<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: DS.Spacing.m) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(DS.Spacing.xxl)
    }
}

private struct ThreatRow: View {
    let threat: Threat
    let onReveal: () -> Void
    let onQuarantine: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            Image(systemName: icon).foregroundStyle(color).font(.title3).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.Spacing.s) {
                    Text(threat.title).font(.headline)
                    Text(threat.severity.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .glassEffect(.regular.tint(color.opacity(0.3)), in: .capsule)
                        .foregroundStyle(color)
                }
                Text(threat.detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let p = threat.path {
                    Text(p.path).font(.dsMono).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            VStack(spacing: DS.Spacing.xs) {
                if threat.path != nil {
                    Button { onReveal() } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.glass).controlSize(.small).help("Finder'da Göster")
                    Button { onQuarantine() } label: { Image(systemName: "trash") }
                        .buttonStyle(.glass).controlSize(.small).help("Karantinaya Al (Çöp)")
                }
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private var color: Color {
        switch threat.severity {
        case .malicious: DS.Palette.danger
        case .suspicious: DS.Palette.caution
        case .info: DS.Palette.accent
        }
    }
    private var icon: String {
        switch threat.severity {
        case .malicious: "xmark.shield.fill"
        case .suspicious: "exclamationmark.shield.fill"
        case .info: "info.circle.fill"
        }
    }
}
