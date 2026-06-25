import SwiftUI
import Observation
import PureGlassKit

@MainActor
@Observable
final class PrivacyViewModel {
    private let scanner = BrowserPrivacyScanner()

    var items: [BrowserPrivacyItem] = []
    var scanning = false
    var scanned = false
    var selected: Set<URL> = []
    var resultMessage: String?

    var grouped: [(browser: String, items: [BrowserPrivacyItem])] {
        Dictionary(grouping: items, by: \.browser)
            .map { (browser: $0.key, items: $0.value) }
            .sorted { ($0.items.reduce(0){$0+$1.size}) > ($1.items.reduce(0){$0+$1.size}) }
    }
    var totalSelected: Int64 { items.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size } }

    func isSelected(_ u: URL) -> Bool { selected.contains(u) }
    func toggle(_ u: URL) { if selected.contains(u) { selected.remove(u) } else { selected.insert(u) } }

    func scan() async {
        scanning = true; scanned = false; resultMessage = nil
        items = await Task.detached { [scanner] in scanner.scan() }.value
        selected = Set(items.map(\.url))   // varsayılan: hepsi seçili
        scanning = false; scanned = true
    }

    func clean() async {
        var trashed = 0
        for url in selected {
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { trashed += 1 }
        }
        resultMessage = L("\(trashed) öğe Çöp'e taşındı", "\(trashed) items moved to Trash")
        await scan()
    }
}

struct PrivacyView: View {
    @State private var model = PrivacyViewModel()

    var body: some View {
        Group {
            if model.scanning { centered { ProgressView().controlSize(.large); Text(L("Tarayıcı verileri taranıyor…", "Scanning browser data…")).foregroundStyle(.secondary) } }
            else if !model.scanned { idle }
            else if model.items.isEmpty { centered { Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(DS.Palette.safe); Text(L("Temizlenecek tarayıcı verisi yok", "No browser data to clean")).font(.dsTitle) } }
            else { results }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idle: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.l) {
                Image(systemName: "hand.raised").font(.system(size: 58, weight: .light)).symbolRenderingMode(.hierarchical).foregroundStyle(.tint)
                Text(L("Tarayıcı Gizliliği", "Browser Privacy")).font(.dsDisplay(34))
                Text(L("Safari, Chrome, Firefox, Brave ve Edge'in önbellek, geçmiş ve çerez verilerini bulup temizler. Her şey Çöp'e gider (geri alınabilir).", "Finds and clears cache, history and cookies for Safari, Chrome, Firefox, Brave and Edge. Everything goes to the Trash (recoverable)."))
                    .font(.iCallout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                Button { Task { await model.scan() } } label: {
                    Label(L("Tarayıcıları Tara", "Scan Browsers"), systemImage: "magnifyingglass").font(.iTitle3).padding(.horizontal, DS.Spacing.l).padding(.vertical, DS.Spacing.s)
                }.buttonStyle(.glassProminent).tint(.accentColor).controlSize(.extraLarge)
            }
            .padding(DS.Spacing.xxl).frame(maxWidth: .infinity)
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.grouped, id: \.browser) { group in
                    Section {
                        ForEach(group.items) { item in
                            HStack(spacing: DS.Spacing.s) {
                                Toggle(isOn: Binding(get: { model.isSelected(item.url) }, set: { _ in model.toggle(item.url) })) { EmptyView() }
                                    .toggleStyle(.checkbox).labelsHidden()
                                Text(item.kind).font(.iCallout)
                                Text(item.url.path).font(.dsMono).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(item.size.formattedBytes).font(.iCallout.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        HStack { Image(systemName: "globe"); Text(group.browser).font(.iHeadline); Spacer()
                            Text(group.items.reduce(Int64(0)){$0+$1.size}.formattedBytes).font(.iSubheadline.weight(.semibold)).foregroundStyle(.secondary) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            HStack {
                Text(L("Seçili: \(model.totalSelected.formattedBytes)", "Selected: \(model.totalSelected.formattedBytes)")).font(.iHeadline)
                if let msg = model.resultMessage { Text(msg).font(.iCaption).foregroundStyle(DS.Palette.safe) }
                Spacer()
                Button(L("Yeniden Tara", "Rescan")) { Task { await model.scan() } }.buttonStyle(.glass)
                Button { Task { await model.clean() } } label: { Label(L("Çöp'e Taşı", "Move to Trash"), systemImage: "trash").padding(.horizontal, DS.Spacing.s) }
                    .buttonStyle(.glassProminent).tint(DS.Palette.danger).disabled(model.selected.isEmpty)
            }
            .padding(DS.Spacing.l)
            .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.l))
            .padding(.horizontal, DS.Spacing.m).padding(.bottom, DS.Spacing.m)
        }
    }

    private func centered<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: DS.Spacing.m) { c() }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(DS.Spacing.xxl)
    }
}
