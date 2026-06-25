import SwiftUI
import AppKit
import Observation
import PureGlassKit

@MainActor
@Observable
final class DuplicateViewModel {
    private let finder = DuplicateFinder()

    var root: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
    var groups: [DuplicateGroup] = []
    var scanning = false
    var scanned = false
    var selectedURLs: Set<URL> = []
    var resultMessage: String?

    private var sizeByURL: [URL: Int64] = [:]

    var totalWasted: Int64 { groups.reduce(0) { $0 + $1.wastedBytes } }
    var totalSelected: Int64 { selectedURLs.reduce(0) { $0 + (sizeByURL[$1] ?? 0) } }

    func isSelected(_ url: URL) -> Bool { selectedURLs.contains(url) }
    func toggle(_ url: URL) {
        if selectedURLs.contains(url) { selectedURLs.remove(url) } else { selectedURLs.insert(url) }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Seç"
        if panel.runModal() == .OK, let url = panel.url { root = url }
    }

    func scan() async {
        scanning = true; scanned = false; groups = []; selectedURLs = []; sizeByURL = [:]; resultMessage = nil
        let found = await finder.find(in: [root])
        groups = found
        for g in found {
            for u in g.urls { sizeByURL[u] = g.size }
            // Varsayılan: ilk kopya tutulur, gerisi seçilir.
            for u in g.urls.dropFirst() { selectedURLs.insert(u) }
        }
        scanning = false; scanned = true
    }

    func clean() async {
        var trashed = 0
        for url in selectedURLs {
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { trashed += 1 }
        }
        resultMessage = "\(trashed) kopya Çöp'e taşındı"
        await scan()
    }
}

struct DuplicateView: View {
    @State private var model = DuplicateViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            content
        }
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Yinelenen Dosyalar").font(.dsTitle)
                Text("Aynı içeriğe sahip dosyaları bulur (içerik karması ile). Bir kopya tutulur, gerisini sen seçip silersin.")
                    .font(.iCaption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button { model.pickFolder() } label: { Label(model.root.lastPathComponent, systemImage: "folder") }
                .buttonStyle(.glass).controlSize(.small)
            Button { Task { await model.scan() } } label: {
                Label("Tara", systemImage: "magnifyingglass")
            }.buttonStyle(.glassProminent).tint(.accentColor).controlSize(.small)
        }
        .padding(DS.Spacing.m)
    }

    @ViewBuilder
    private var content: some View {
        if model.scanning {
            centered { ProgressView().controlSize(.large); Text("Yinelenenler aranıyor…").foregroundStyle(.secondary) }
        } else if !model.scanned {
            centered {
                Image(systemName: "doc.on.doc").font(.system(size: 56, weight: .light)).symbolRenderingMode(.hierarchical).foregroundStyle(.tint)
                Text("Bir klasör seç ve tara").font(.dsTitle)
                Text("Varsayılan: \(model.root.path)").font(.iCaption).foregroundStyle(.tertiary)
            }
        } else if model.groups.isEmpty {
            centered {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(DS.Palette.safe)
                Text("Yinelenen dosya bulunamadı").font(.dsTitle)
            }
        } else {
            VStack(spacing: 0) {
                List {
                    ForEach(model.groups) { group in
                        Section {
                            ForEach(Array(group.urls.enumerated()), id: \.element) { idx, url in
                                row(url, size: group.size, isFirst: idx == 0)
                            }
                        } header: {
                            HStack {
                                Text("\(group.urls.count) kopya").font(.iHeadline)
                                Spacer()
                                Text("\(group.wastedBytes.formattedBytes) boşa").font(.iSubheadline.weight(.semibold)).foregroundStyle(DS.Palette.caution)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                cleanBar
            }
        }
    }

    private func row(_ url: URL, size: Int64, isFirst: Bool) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Toggle(isOn: Binding(get: { model.isSelected(url) }, set: { _ in model.toggle(url) })) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Spacing.s) {
                    Text(url.lastPathComponent).font(.iCallout).lineLimit(1)
                    if isFirst { Text("tutulacak").font(.iCaption2).foregroundStyle(DS.Palette.safe) }
                }
                Text(url.path).font(.dsMono).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(size.formattedBytes).font(.iCallout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var cleanBar: some View {
        HStack(spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Seçili: \(model.totalSelected.formattedBytes)").font(.iHeadline)
                Text("Toplam boşa: \(model.totalWasted.formattedBytes)").font(.iCaption).foregroundStyle(.secondary)
            }
            if let msg = model.resultMessage { Text(msg).font(.iCaption).foregroundStyle(DS.Palette.safe) }
            Spacer()
            Button { Task { await model.clean() } } label: {
                Label("Çöp'e Taşı", systemImage: "trash").padding(.horizontal, DS.Spacing.s)
            }
            .buttonStyle(.glassProminent).tint(DS.Palette.danger).disabled(model.selectedURLs.isEmpty)
        }
        .padding(DS.Spacing.l)
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.l))
        .padding(.horizontal, DS.Spacing.m).padding(.bottom, DS.Spacing.m)
    }

    private func centered<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: DS.Spacing.m) { c() }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(DS.Spacing.xxl)
    }
}
