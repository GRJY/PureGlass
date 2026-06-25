import SwiftUI
import AppKit
import PureGlassKit

/// Akıllı Tarama akışı: tara → sonuçlar (yol+boyut+risk, seçim) → Çöp'e taşı → canlı log → özet.
struct SmartScanView: View {
    @Bindable var model: AppViewModel
    @State private var showConfirm = false

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
                    Text(L("Akıllı Tarama", "Smart Scan"))
                        .font(.dsDisplay(40))
                    Text(L("Uygulamaların biriktirdiği geçici dosya, önbellek ve eski kayıtları bulur. Onaylamadan hiçbir şey silinmez; silinenler Çöp'e gider.", "Finds temp files, caches and old logs apps pile up. Nothing is deleted without your OK; deleted items go to the Trash."))
                        .font(.iCallout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }

                if !model.permissions.isGranted {
                    FullDiskAccessCard(coordinator: model.permissions)
                        .frame(maxWidth: 560)
                }

                deepCleanCard
                    .frame(maxWidth: 560)

                Button {
                    Task { await model.scan() }
                } label: {
                    Label(L("Taramayı Başlat", "Start Scan"), systemImage: "magnifyingglass")
                        .font(.iTitle3)
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

    private var deepCleanCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                Toggle(isOn: $model.deepClean) {
                    Label(L("Derin Sistem Temizliği", "Deep System Clean"), systemImage: "shield.lefthalf.filled")
                        .font(.dsTitle)
                }
                .toggleStyle(.switch)
                .tint(.accentColor)

                Text(.init(L("Sistem önbellek ve günlüklerini de tarar. Silme için **yönetici parolası** gerekir ve bu öğeler **kalıcı** silinir (sistem yeniden üretir). `/System` gibi korumalı dosyalara asla dokunulmaz.", "Also scans system caches and logs. Deleting them needs an **admin password** and these items are removed **permanently** (the system regenerates them). Protected files like `/System` are never touched.")))
                    .font(.iCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Tarama

    private var scanning: some View {
        VStack(spacing: DS.Spacing.l) {
            ProgressRing(progress: model.scanProgress, size: 140)
            Text(L("Taranıyor…", "Scanning…")).font(.dsTitle)
            Text(model.scanStatusText)
                .font(.iCallout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(model.scanBytesFound.formattedBytes) bulundu")
                .font(.iHeadline.monospacedDigit())
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
        }
        .padding(DS.Spacing.xxl)
    }

    // MARK: - Sonuçlar

    private var results: some View {
        VStack(spacing: 0) {
            if model.lockedCategories > 0 {
                lockedBanner
            }
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
        .alert(L("Bu işlem geri alınamayabilir", "This action may be irreversible"), isPresented: $showConfirm) {
            Button(L("Sil", "Delete"), role: .destructive) { Task { await model.clean() } }
            Button(L("Vazgeç", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Seçiminde riskli (sarı/kırmızı) öğeler var. Sistem (kırmızı) öğeleri KALICI silinir ve geri alınamaz. Silmek istediğine emin misin?", "Your selection has risky (yellow/red) items. System (red) items are deleted PERMANENTLY and can't be undone. Are you sure?"))
        }
    }

    private var lockedBanner: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: "lock.fill").foregroundStyle(DS.Palette.caution)
            Text(L("\(model.lockedCategories) kategori Tam Disk Erişimi olmadan atlandı.", "\(model.lockedCategories) categories skipped without Full Disk Access."))
                .font(.iCallout)
            Spacer()
            Button(L("Ayarları Aç", "Open Settings")) {
                NSWorkspace.shared.open(model.permissions.settingsURL)
                model.permissions.startPolling()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.s)
        .glassEffect(.regular.tint(DS.Palette.caution.opacity(0.28)), in: .capsule)
        .padding(.horizontal, DS.Spacing.m)
        .padding(.top, DS.Spacing.s)
    }

    private var emptyResults: some View {
        VStack(spacing: DS.Spacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(DS.Palette.safe)
            Text(L("Temizlenecek bir şey bulunamadı", "Nothing to clean was found"))
                .font(.dsTitle)
            Text(L("Sistemin zaten temiz görünüyor.", "Your system already looks clean."))
                .foregroundStyle(.secondary)
            Button(L("Tekrar Tara", "Scan Again")) { Task { await model.scan() } }
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
            Text(result.title).font(.iHeadline)
            RiskBadge(level: result.risk)
            Spacer()
            Text(result.totalSize.formattedBytes)
                .font(.iSubheadline.weight(.semibold))
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
                .font(.iCaption)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(.iCallout)
                    .lineLimit(1)
                Text(item.url.path)
                    .font(.dsMono)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.size.formattedBytes)
                .font(.iCallout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var cleanBar: some View {
        HStack(spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Seçili: \(model.totalSelectedSize.formattedBytes)", "Selected: \(model.totalSelectedSize.formattedBytes)"))
                    .font(.iHeadline)
                Text(L("Toplam bulunan: \(model.totalFoundSize.formattedBytes)", "Total found: \(model.totalFoundSize.formattedBytes)"))
                    .font(.iCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Yeniden Tara", "Rescan")) { Task { await model.scan() } }
                .buttonStyle(.glass)
            Button {
                if model.hasRiskySelection { showConfirm = true } else { Task { await model.clean() } }
            } label: {
                Label(L("Çöp'e Taşı", "Move to Trash"), systemImage: "trash")
                    .padding(.horizontal, DS.Spacing.s)
            }
            .buttonStyle(.glassProminent)
            .tint(DS.Palette.danger)
            .disabled(model.selectedItems.isEmpty)
        }
        .padding(DS.Spacing.l)
        // Yüzen gerçek Liquid Glass çubuk.
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.l))
        .padding(.horizontal, DS.Spacing.m)
        .padding(.bottom, DS.Spacing.m)
    }

    // MARK: - Temizlik (canlı log)

    private var cleaning: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            HStack(spacing: DS.Spacing.m) {
                ProgressView().controlSize(.large)
                Text(L("Çöp'e taşınıyor…", "Moving to Trash…")).font(.dsTitle)
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
            Text(L("Temizlik tamamlandı", "Cleanup complete"))
                .font(.dsDisplay(32))

            if let report = model.report {
                HStack(spacing: DS.Spacing.m) {
                    StatTile(title: L("Geri kazanılan", "Reclaimed"), value: report.bytesReclaimed.formattedBytes,
                             systemImage: "internaldrive", tint: DS.Palette.safe)
                    StatTile(title: L("Çöp'e taşınan", "Moved to Trash"), value: "\(report.trashedCount)",
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
                    Label(L("Çöp'ü Göster", "Show Trash"), systemImage: "trash")
                }
                .buttonStyle(.glass)

                Button(L("Tekrar Tara", "Scan Again")) { Task { await model.scan() } }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
            }
            Text(L("Silinenler Çöp Kutusu'nda — geri almak için sürükleyebilirsin.", "Deleted items are in the Trash — drag them out to restore."))
                .font(.iCaption)
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
                Text(L("Ayarlar", "Settings")).font(.dsDisplay(32))
                FullDiskAccessCard(coordinator: model.permissions)
                GlassCard {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        Label("Gizlilik", systemImage: "hand.raised")
                            .font(.dsTitle)
                        Text(L("PureGlass tamamen lokalde çalışır. Hiçbir veri internete gönderilmez, telemetri yoktur. Tüm silmeler Çöp Kutusu'na taşınır (geri alınabilir).", "PureGlass runs entirely locally. No data is sent to the internet, no telemetry. All deletions go to the Trash (recoverable)."))
                            .font(.iCallout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GlassCard {
                    HStack {
                        Label(L("Sürüm", "Version"), systemImage: "info.circle")
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
