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
            resultMessage = L("\(path.lastPathComponent) karantinaya alındı (Çöp Kutusu)", "\(path.lastPathComponent) quarantined (Trash)")
        } catch {
            resultMessage = L("Karantina başarısız (yetki gerekebilir): \(error.localizedDescription)", "Quarantine failed (may need privileges): \(error.localizedDescription)")
        }
    }

    func reveal(_ threat: Threat) {
        if let p = threat.path { NSWorkspace.shared.activateFileViewerSelecting([p]) }
    }
}

struct SecurityView: View {
    @State private var model = SecurityViewModel()

    var body: some View {
        Group {
            if model.scanning { scanning }
            else if !model.scanned { idle }
            else if model.threats.isEmpty { clean }
            else { results }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DS.Anim.smooth, value: model.scanning)
        .animation(DS.Anim.smooth, value: model.scanned)
    }

    private var idle: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.l) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 60, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(L("Güvenlik Taraması", "Security Scan")).font(.dsDisplay(36))
                Text(L("Açılışta arka planda çalışan gizli programları bulur, Apple onaylı olup olmadıklarını denetler ve şüphelileri işaretler. Tüm veriler cihazında kalır.", "Finds hidden programs that run in the background at startup, checks whether each is Apple-approved, and flags the suspicious ones. All data stays on your device."))
                    .font(.iCallout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 460)
                Button { Task { await model.scan() } } label: {
                    Label(L("Taramayı Başlat", "Start Scan"), systemImage: "shield")
                        .font(.iTitle3)
                        .padding(.horizontal, DS.Spacing.l).padding(.vertical, DS.Spacing.s)
                }
                .buttonStyle(.glassProminent).tint(.accentColor).controlSize(.extraLarge)
            }
            .padding(DS.Spacing.xxl).frame(maxWidth: .infinity)
        }
    }

    private var scanning: some View {
        VStack(spacing: DS.Spacing.m) {
            ProgressView().controlSize(.large)
            Text(L("Tehditler taranıyor…", "Scanning for threats…")).foregroundStyle(.secondary)
        }
        .padding(DS.Spacing.xxl)
    }

    private var clean: some View {
        VStack(spacing: DS.Spacing.m) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 64)).foregroundStyle(DS.Palette.safe)
            Text(L("Tehdit bulunamadı", "No threats found")).font(.dsDisplay(30))
            Text(L("Bilinen göstergeler ve şüpheli kalıcı görevler bulunamadı.", "No known indicators or suspicious persistence found.")).foregroundStyle(.secondary)
            Button(L("Tekrar Tara", "Scan Again")) { Task { await model.scan() } }.buttonStyle(.glass)
        }
        .padding(DS.Spacing.xxl)
    }

    private var results: some View {
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
                Label(L("\(model.threats.count) bulgu", "\(model.threats.count) findings"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.Palette.caution)
                if let msg = model.resultMessage {
                    Text(msg).font(.iCaption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Tekrar Tara", "Scan Again")) { Task { await model.scan() } }.buttonStyle(.glass)
            }
            .padding(DS.Spacing.l)
            .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.l))
            .padding(.horizontal, DS.Spacing.m).padding(.bottom, DS.Spacing.m)
        }
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
                    Text(threat.title).font(.iHeadline)
                    Text(threat.severity.title)
                        .font(.iCaption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .glassEffect(.regular.tint(color.opacity(0.3)), in: .capsule)
                        .foregroundStyle(color)
                }
                Text(threat.detail).font(.iCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let p = threat.path {
                    Text(p.path).font(.dsMono).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            VStack(spacing: DS.Spacing.xs) {
                if threat.path != nil {
                    Button { onReveal() } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.glass).controlSize(.small).help(L("Finder'da Göster", "Show in Finder"))
                    Button { onQuarantine() } label: { Image(systemName: "trash") }
                        .buttonStyle(.glass).controlSize(.small).help(L("Karantinaya Al (Çöp)", "Quarantine (Trash)"))
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
