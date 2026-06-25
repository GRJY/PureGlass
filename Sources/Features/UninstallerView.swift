import SwiftUI
import AppKit
import Observation
import PureGlassKit

@MainActor
@Observable
final class UninstallerViewModel {
    private let finder = AppFinder()
    private let leftoverFinder = AppLeftoverFinder()

    var apps: [InstalledApp] = []
    var loading = false
    var search = ""
    var selected: InstalledApp?
    var leftovers: [DiskMapEntry] = []
    var removing = false
    var resultMessage: String?

    var filtered: [InstalledApp] {
        let base = apps.filter { !$0.isAppleApp }   // Apple uygulamaları kaldırılamaz
        guard !search.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var totalRemovalSize: Int64 {
        (selected?.size ?? 0) + leftovers.reduce(0) { $0 + $1.size }
    }

    func load() async {
        loading = true
        apps = await finder.installedApps()
        loading = false
    }

    func select(_ app: InstalledApp) {
        leftovers = leftoverFinder.leftovers(for: app)
        selected = app
    }

    func uninstall() async {
        guard let app = selected else { return }
        removing = true
        let urls = [app.url] + leftovers.map(\.url)
        var trashed = 0, failed = 0
        for url in urls {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil); trashed += 1 }
            catch { failed += 1 }
        }
        resultMessage = L("\(app.name): \(trashed) öğe Çöp'e taşındı", "\(app.name): \(trashed) items moved to Trash") + (failed > 0 ? L(" • \(failed) başarısız (yetki gerekebilir)", " • \(failed) failed (may need privileges)") : "")
        removing = false
        selected = nil
        await load()
    }
}

struct UninstallerView: View {
    @State private var model = UninstallerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            if model.loading {
                loadingView
            } else {
                appList
            }
        }
        .task { if model.apps.isEmpty { await model.load() } }
        .sheet(item: Binding(get: { model.selected }, set: { if $0 == nil { model.selected = nil } })) { app in
            UninstallSheet(model: model, app: app)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Uygulama Kaldırıcı", "App Uninstaller")).font(.dsTitle)
                Text(L("Uygulamayı, geride bıraktığı ayar ve veri artıklarıyla birlikte eksiksiz kaldırır. Önce neyi sileceğini gösterir.", "Removes an app completely, along with the settings and data leftovers it leaves behind. Shows you what will be deleted first."))
                    .font(.iCaption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let msg = model.resultMessage {
                Text(msg).font(.iCaption).foregroundStyle(DS.Palette.safe)
            }
        }
        .padding(DS.Spacing.m)
    }

    private var loadingView: some View {
        VStack(spacing: DS.Spacing.m) {
            ProgressView().controlSize(.large)
            Text(L("Uygulamalar taranıyor…", "Scanning apps…")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appList: some View {
        List {
            ForEach(model.filtered) { app in
                Button { model.select(app) } label: {
                    HStack(spacing: DS.Spacing.m) {
                        AppIcon(url: app.url)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).font(.iBody)
                            if let bid = app.bundleID {
                                Text(bid).font(.iCaption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(app.size.formattedBytes)
                            .font(.iCallout.monospacedDigit()).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.iCaption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $model.search, prompt: L("Uygulama ara", "Search apps"))
    }
}

/// Kaldırma onay paneli — gerçek Liquid Glass kart.
struct UninstallSheet: View {
    @Bindable var model: UninstallerViewModel
    let app: InstalledApp

    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            HStack(spacing: DS.Spacing.m) {
                AppIcon(url: app.url, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.dsTitle)
                    Text(L("Toplam kaldırılacak: \(model.totalRemovalSize.formattedBytes)", "Total to remove: \(model.totalRemovalSize.formattedBytes)"))
                        .font(.iCallout).foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(L("Kaldırılacak öğeler", "Items to remove")).font(.iHeadline)
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        itemRow(name: "\(app.name).app", path: app.url.path, size: app.size, icon: "app.fill")
                        ForEach(model.leftovers) { lo in
                            itemRow(name: lo.url.lastPathComponent, path: lo.url.path, size: lo.size,
                                    icon: lo.isDirectory ? "folder" : "doc")
                        }
                    }
                    .padding(DS.Spacing.s)
                }
                .frame(maxHeight: 240)
                .glassEffect(.regular.tint(.black.opacity(0.22)), in: .rect(cornerRadius: DS.Radius.m))
            }

            if model.leftovers.isEmpty {
                Text(L("Bu uygulama için ek artık bulunamadı.", "No extra leftovers found for this app."))
                    .font(.iCaption).foregroundStyle(.tertiary)
            }

            HStack(spacing: DS.Spacing.m) {
                Button(L("Vazgeç", "Cancel")) { model.selected = nil }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                Button {
                    Task { await model.uninstall() }
                } label: {
                    Label(model.removing ? L("Kaldırılıyor…", "Removing…") : L("Çöp'e Taşı", "Move to Trash"), systemImage: "trash")
                        .padding(.horizontal, DS.Spacing.s)
                }
                .buttonStyle(.glassProminent)
                .tint(DS.Palette.danger)
                .controlSize(.large)
                .disabled(model.removing)
            }
        }
        .padding(DS.Spacing.xl)
        .frame(width: 540)
    }

    private func itemRow(name: String, path: String, size: Int64, icon: String) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: icon).font(.iCaption).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.iCallout).lineLimit(1)
                Text(path).font(.dsMono).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(size.formattedBytes).font(.iCaption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

/// Bir uygulamanın gerçek Finder ikonunu gösterir.
struct AppIcon: View {
    let url: URL
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}
