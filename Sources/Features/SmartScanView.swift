import SwiftUI
import AppKit
import PureGlassKit

/// Akıllı Tarama akışı: tara → sonuçlar (yol+boyut+risk, seçim) → Çöp'e taşı → canlı log → özet.
struct SmartScanView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        Group {
            switch model.phase {
            case .idle: idle
            case .scanning: scanning
            case .results: results
            case .cleaning: cleaning
            case .done: done
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DS.Anim.smooth, value: model.phase)
    }

    // MARK: - Boşta

    private var idle: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                VStack(spacing: DS.Spacing.s) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 60, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                    Text("Akıllı Tarama")
                        .font(.dsDisplay(40))
                    Text("Önbellek, günlük ve geçici dosyaları güvenle tarar.\nHer dosya yolunu görür, silmeden önce onaylarsın.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !model.permissions.isGranted {
                    FullDiskAccessCard(coordinator: model.permissions)
                        .frame(maxWidth: 560)
                }

                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Taramayı Başlat", systemImage: "magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, DS.Spacing.l)
                        .padding(.vertical, DS.Spacing.s)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .controlSize(.extraLarge)
            }
            .padding(DS.Spacing.xxl)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Tarama

    private var scanning: some View {
        VStack(spacing: DS.Spacing.l) {
            ProgressRing(progress: model.scanProgress, size: 140)
            Text("Taranıyor…").font(.dsTitle)
            Text(model.scanStatusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(DS.Spacing.xxl)
    }

    // MARK: - Sonuçlar

    private var results: some View {
        VStack(spacing: 0) {
            if model.results.isEmpty {
                emptyResults
            } else {
                List {
                    ForEach(model.results) { result in
                        Section {
                            ForEach(result.items) { item in
                                itemRow(item)
                            }
                        } header: {
                            categoryHeader(result)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            cleanBar
        }
    }

    private var emptyResults: some View {
        VStack(spacing: DS.Spacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(DS.Palette.safe)
            Text("Temizlenecek bir şey bulunamadı")
                .font(.dsTitle)
            Text("Sistemin zaten temiz görünüyor.")
                .foregroundStyle(.secondary)
            Button("Tekrar Tara") { Task { await model.scan() } }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func categoryHeader(_ result: CategoryScanResult) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Toggle(isOn: Binding(
                get: { model.selectionState(of: result) },
                set: { _ in model.toggleCategory(result) }
            )) { EmptyView() }
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: result.category.symbolName)
                .foregroundStyle(.tint)
            Text(result.title).font(.headline)
            RiskBadge(level: result.risk)
            Spacer()
            Text(result.totalSize.formattedBytes)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func itemRow(_ item: FileItem) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Toggle(isOn: Binding(
                get: { model.isSelected(item) },
                set: { _ in model.toggle(item) }
            )) { EmptyView() }
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundStyle(.secondary)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                Text(item.url.path)
                    .font(.dsMono)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.size.formattedBytes)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var cleanBar: some View {
        HStack(spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Seçili: \(model.totalSelectedSize.formattedBytes)")
                    .font(.headline)
                Text("Toplam bulunan: \(model.totalFoundSize.formattedBytes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Yeniden Tara") { Task { await model.scan() } }
                .buttonStyle(.glass)
            Button {
                Task { await model.clean() }
            } label: {
                Label("Çöp'e Taşı", systemImage: "trash")
                    .padding(.horizontal, DS.Spacing.s)
            }
            .buttonStyle(.glassProminent)
            .tint(DS.Palette.danger)
            .disabled(model.selectedItems.isEmpty)
        }
        .padding(DS.Spacing.l)
        .background(.ultraThinMaterial)
    }

    // MARK: - Temizlik (canlı log)

    private var cleaning: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            HStack(spacing: DS.Spacing.m) {
                ProgressView().controlSize(.large)
                Text("Çöp'e taşınıyor…").font(.dsTitle)
            }
            LiveLogPanel(lines: model.logLines, height: 400)
        }
        .padding(DS.Spacing.xxl)
    }

    // MARK: - Özet

    private var done: some View {
        VStack(spacing: DS.Spacing.l) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(DS.Palette.safe)
            Text("Temizlik tamamlandı")
                .font(.dsDisplay(32))

            if let report = model.report {
                HStack(spacing: DS.Spacing.m) {
                    StatTile(title: "Geri kazanılan", value: report.bytesReclaimed.formattedBytes,
                             systemImage: "internaldrive", tint: DS.Palette.safe)
                    StatTile(title: "Çöp'e taşınan", value: "\(report.trashedCount)",
                             systemImage: "trash")
                    if report.skippedCount + report.failedCount > 0 {
                        StatTile(title: "Atlanan/Hata", value: "\(report.skippedCount + report.failedCount)",
                                 systemImage: "exclamationmark.triangle", tint: DS.Palette.caution)
                    }
                }
                .frame(maxWidth: 640)
            }

            HStack(spacing: DS.Spacing.m) {
                Button {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash"))
                } label: {
                    Label("Çöp'ü Göster", systemImage: "trash")
                }
                .buttonStyle(.glass)

                Button("Tekrar Tara") { Task { await model.scan() } }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
            }
            Text("Silinenler Çöp Kutusu'nda — geri almak için sürükleyebilirsin.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(DS.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Basit ayarlar ekranı.
struct SettingsView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                Text("Ayarlar").font(.dsDisplay(32))
                FullDiskAccessCard(coordinator: model.permissions)
                GlassCard {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        Label("Gizlilik", systemImage: "hand.raised")
                            .font(.dsTitle)
                        Text("PureGlass tamamen lokalde çalışır. Hiçbir veri internete gönderilmez, telemetri yoktur. Tüm silmeler Çöp Kutusu'na taşınır (geri alınabilir).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GlassCard {
                    HStack {
                        Label("Sürüm", systemImage: "info.circle")
                        Spacer()
                        Text("PureGlass • PureGlassKit \(PureGlassKitInfo.version)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(DS.Spacing.xxl)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }
}
