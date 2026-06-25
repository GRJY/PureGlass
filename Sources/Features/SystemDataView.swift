import SwiftUI
import AppKit
import Observation
import PureGlassKit

@MainActor
@Observable
final class SystemDataViewModel {
    enum Phase: Equatable { case idle, scanning, results, cleaning, done }

    private let database = LocationsDatabase()
    private let scanEngine = ScanEngine()
    private let cleaningEngine: CleaningEngine
    private let privilegedCleaner: PrivilegedCleaner

    var phase: Phase = .idle
    var results: [CategoryScanResult] = []
    var selectedURLs: Set<URL> = []     // MANUEL: hiçbir şey önceden seçili değil
    let trickle = ProgressTrickler()
    var progress: Double { trickle.value }
    var bytesFound: Int64 = 0
    var statusText = ""
    var logLines: [LogLine] = []
    var report: CleanReport?

    var snapshotCount = 0
    var snapshotBusy = false

    var protectedResults: [DiskMapEntry] = []
    var protectedLoading = false
    var protectedTotal: Int64 { protectedResults.reduce(0) { $0 + $1.size } }

    /// macOS'un çalışması için gerekli, silinemez korumalı alanlar.
    private let protectedLocations: [(String, String)] = [
        (L("Sistem Çerçeveleri", "System Frameworks"), "/System/Library/Frameworks"),
        (L("Özel Sistem Çerçeveleri", "Private System Frameworks"), "/System/Library/PrivateFrameworks"),
        (L("Yerleşik Uygulamalar", "Built-in Apps"), "/System/Applications"),
        (L("Sistem Veritabanları", "System Databases"), "/private/var/db"),
        (L("Sistem Kütüphaneleri", "System Libraries"), "/usr/lib"),
        (L("Apple Sistem İçeriği", "Apple System Content"), "/Library/Apple"),
    ]

    /// Seçimde sarı (dikkat) veya kırmızı (riskli) öğe var mı?
    var hasRiskySelection: Bool {
        selectedItems.contains { $0.risk == .caution || $0.risk == .danger }
    }

    init() {
        // Geniş SafetyGuard: sistem-veri köklerinin ALT öğeleri silinebilir (hepsi trash-first / geri alınabilir).
        cleaningEngine = CleaningEngine(safety: SafetyGuard(allowedRoots: database.systemData.map(\.url)))
        privilegedCleaner = PrivilegedCleaner(
            safety: SafetyGuard(allowedRoots: database.systemData.filter(\.requiresRoot).map(\.url)))
    }

    var allItems: [FileItem] { results.flatMap(\.items) }
    var selectedItems: [FileItem] { allItems.filter { selectedURLs.contains($0.url) } }
    var totalFound: Int64 { results.reduce(0) { $0 + $1.totalSize } }
    var totalSelected: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func isSelected(_ item: FileItem) -> Bool { selectedURLs.contains(item.url) }
    func toggle(_ item: FileItem) {
        if selectedURLs.contains(item.url) { selectedURLs.remove(item.url) } else { selectedURLs.insert(item.url) }
    }
    func selectionState(of r: CategoryScanResult) -> Bool {
        !r.items.isEmpty && r.items.allSatisfy { selectedURLs.contains($0.url) }
    }
    func toggleCategory(_ r: CategoryScanResult) {
        let urls = r.items.map(\.url)
        if urls.allSatisfy(selectedURLs.contains) { urls.forEach { selectedURLs.remove($0) } }
        else { urls.forEach { selectedURLs.insert($0) } }
    }

    func refreshSnapshots() {
        snapshotCount = TimeMachineService.localSnapshotDates().count
    }

    func deleteSnapshots() async {
        snapshotBusy = true
        try? TimeMachineService.deleteAllLocalSnapshots()
        refreshSnapshots()
        snapshotBusy = false
    }

    func scan() async {
        phase = .scanning; results = []; selectedURLs = []; logLines = []; report = nil
        bytesFound = 0; statusText = L("Başlatılıyor…", "Starting…")
        trickle.start()
        let scanned = await scanEngine.scan(database.systemData) { [weak self] p in
            await MainActor.run { self?.trickle.report(p.fraction); self?.statusText = p.currentTitle; self?.bytesFound = p.bytesFound }
        }
        trickle.finish()
        results = scanned.filter { $0.isAccessible && !$0.items.isEmpty }
        phase = .results
        Task { await measureProtected() }   // silinemez alanı arka planda hesapla (engellemez)
    }

    func measureProtected() async {
        protectedLoading = true
        protectedResults = []
        let scanner = DiskMapScanner()
        await withTaskGroup(of: DiskMapEntry?.self) { group in
            for (title, path) in protectedLocations {
                group.addTask {
                    let url = URL(filePath: path)
                    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                    let kids = await scanner.children(of: url)
                    let total = kids.reduce(Int64(0)) { $0 + $1.size }
                    guard total > 0 else { return nil }
                    return DiskMapEntry(url: url, name: title, size: total, isDirectory: true, fileCount: 0)
                }
            }
            for await entry in group {
                if let entry {
                    protectedResults.append(entry)
                    protectedResults.sort { $0.size > $1.size }
                }
            }
        }
        protectedLoading = false
    }

    func clean() async {
        guard !selectedItems.isEmpty else { return }
        phase = .cleaning; logLines = []
        let rootItems = selectedItems.filter(\.requiresRoot)
        let userItems = selectedItems.filter { !$0.requiresRoot }
        let userReport = await cleaningEngine.clean(userItems) { [weak self] e in
            await MainActor.run { self?.logLines.append(LogLine(event: e)) }
        }
        var events = userReport.events
        if !rootItems.isEmpty { events += await cleanPrivileged(rootItems) }
        report = CleanReport(events: events)
        phase = .done
    }

    private func cleanPrivileged(_ items: [FileItem]) async -> [CleanEvent] {
        let (valid, skipped) = privilegedCleaner.partition(items)
        var events = skipped.map { CleanEvent(url: $0.url, size: $0.size, outcome: .skippedUnsafe(L("güvensiz", "unsafe"))) }
        guard let cmd = privilegedCleaner.buildCommand(for: valid.map(\.url)) else { return events }
        do {
            try AdminShell.run(cmd)
            for it in valid {
                let e = CleanEvent(url: it.url, size: it.size, outcome: .trashed)
                events.append(e); logLines.append(LogLine(event: e))
            }
        } catch {
            for it in valid {
                let e = CleanEvent(url: it.url, size: it.size, outcome: .failed(error.localizedDescription))
                events.append(e); logLines.append(LogLine(event: e))
            }
        }
        return events
    }
}

struct SystemDataView: View {
    @State private var model = SystemDataViewModel()
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
        .task {
            model.refreshSnapshots()
            if ProcessInfo.processInfo.environment["PUREGLASS_AUTOSCAN"] == "1", model.phase == .idle {
                await model.scan()
            }
        }
    }

    /// Time Machine yerel anlık görüntüleri — L("Sistem Verileri", "System Data")nin en büyük gizli bileşeni.
    @ViewBuilder
    private var snapshotCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                HStack {
                    Label(L("Time Machine Anlık Görüntüleri", "Time Machine Snapshots"), systemImage: "clock.arrow.2.circlepath")
                        .font(.dsTitle)
                    Spacer()
                    Text(L("\(model.snapshotCount) adet", "\(model.snapshotCount) items"))
                        .font(.iCaption.weight(.semibold))
                        .foregroundStyle(model.snapshotCount > 0 ? DS.Palette.caution : DS.Palette.safe)
                }
                Text(L("Time Machine'in Mac'ine geçici olarak kaydettiği yedek kopyalar. Genellikle \"Sistem Verileri\"nin en büyük parçasıdır ama normal dosya gibi görünmedikleri için listede çıkmazlar. macOS bunları 24 saat içinde kendisi siler; istersen şimdi temizleyebilirsin — tamamen güvenlidir, zaten boş alan olarak sayılırlar.", "Backup copies Time Machine temporarily saves to your Mac. They're usually the biggest part of \"System Data\" but don't show in the list because they don't look like normal files. macOS deletes them itself within 24 hours; you can clear them now if you like — it's completely safe, they already count as free space."))
                    .font(.iCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.snapshotCount > 0 {
                    Button {
                        Task { await model.deleteSnapshots() }
                    } label: {
                        Label(model.snapshotBusy ? "Siliniyor…" : L("Anlık Görüntüleri Sil", "Delete Snapshots"),
                              systemImage: "trash").padding(.horizontal, DS.Spacing.s)
                    }
                    .buttonStyle(.glassProminent).tint(DS.Palette.caution).disabled(model.snapshotBusy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 560)
    }

    private var idle: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.l) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 58, weight: .light)).symbolRenderingMode(.hierarchical).foregroundStyle(.tint)
                Text(L("Sistem Verileri", "System Data")).font(.dsDisplay(38))
                Text(L("Depolama'daki gizemli \"Sistem Verileri\"nin içinde ne var, gösterir: önbellek, iOS yedekleri, geliştirici dosyaları. Hiçbiri otomatik seçilmez — neyi sileceğine sen karar verirsin.", "Shows what's inside the mysterious \"System Data\" in Storage: caches, iOS backups, developer files. Nothing is auto-selected — you decide what to delete."))
                    .font(.iCallout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                GlassCard {
                    HStack(spacing: DS.Spacing.m) {
                        RiskBadge(level: .safe); Text(L("güvenle silinir", "safe to delete")).font(.iCaption).foregroundStyle(.secondary)
                        RiskBadge(level: .caution); Text(L("dikkatli", "caution")).font(.iCaption).foregroundStyle(.secondary)
                        RiskBadge(level: .danger); Text(L("veri kaybı olabilir", "may cause data loss")).font(.iCaption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 560)
                snapshotCard
                Button { Task { await model.scan() } } label: {
                    Label(L("Dosya-tabanlı Sistem Verilerini Tara", "Scan File-based System Data"), systemImage: "magnifyingglass")
                        .font(.iTitle3).padding(.horizontal, DS.Spacing.l).padding(.vertical, DS.Spacing.s)
                }
                .buttonStyle(.glassProminent).tint(.accentColor).controlSize(.extraLarge)
            }
            .padding(DS.Spacing.xxl).frame(maxWidth: .infinity)
        }
    }

    private var scanning: some View {
        VStack(spacing: DS.Spacing.l) {
            ProgressRing(progress: model.progress, size: 140)
            Text(L("Sistem verileri taranıyor…", "Scanning system data…")).font(.dsTitle)
            Text(model.statusText).font(.iCallout).foregroundStyle(.secondary).lineLimit(1)
            Text(L("\(model.bytesFound.formattedBytes) bulundu", "\(model.bytesFound.formattedBytes) found")).font(.iHeadline.monospacedDigit()).foregroundStyle(.tint)
        }
        .padding(DS.Spacing.xxl)
    }

    private var results: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.results) { result in
                    Section {
                        ForEach(result.items) { item in itemRow(item) }
                    } header: { categoryHeader(result) }
                }
                protectedSection
            }
            .scrollContentBackground(.hidden)
            cleanBar
        }
        .alert(L("Bu işlem geri alınamayabilir", "This action may be irreversible"), isPresented: $showConfirm) {
            Button(L("Sil", "Delete"), role: .destructive) { Task { await model.clean() } }
            Button(L("Vazgeç", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Seçiminde riskli (sarı/kırmızı) öğeler var. Kırmızı sistem öğeleri KALICI silinir ve geri alınamaz. Silmek istediğine emin misin?", "Your selection has risky (yellow/red) items. Red system items are deleted PERMANENTLY and can't be undone. Are you sure?"))
        }
    }

    /// Read-only: macOS'un silinemeyen korumalı alanları (yanında boyut).
    @ViewBuilder
    private var protectedSection: some View {
        Section {
            if model.protectedLoading && model.protectedResults.isEmpty {
                HStack(spacing: DS.Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text(L("Korumalı alan hesaplanıyor…", "Calculating protected space…")).font(.iCallout).foregroundStyle(.secondary)
                }
            }
            ForEach(model.protectedResults) { p in
                HStack(spacing: DS.Spacing.s) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).font(.iCaption).frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.iCallout)
                        Text(p.url.path).font(.dsMono).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(p.size.formattedBytes).font(.iCallout.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                Text(L("Silinemez Sistem Verileri", "Undeletable System Data")).font(.iHeadline)
                Text(L("macOS gerektirir", "Requires macOS")).font(.iCaption2).foregroundStyle(.tertiary)
                Spacer()
                if model.protectedTotal > 0 {
                    Text(model.protectedTotal.formattedBytes).font(.iSubheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, DS.Spacing.xs)
        }
    }

    private func categoryHeader(_ result: CategoryScanResult) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Toggle(isOn: Binding(get: { model.selectionState(of: result) }, set: { _ in model.toggleCategory(result) })) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden()
            Image(systemName: result.category.symbolName).foregroundStyle(.tint)
            Text(result.title).font(.iHeadline)
            RiskBadge(level: result.risk)
            Spacer()
            Text(result.totalSize.formattedBytes).font(.iSubheadline.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func itemRow(_ item: FileItem) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Toggle(isOn: Binding(get: { model.isSelected(item) }, set: { _ in model.toggle(item) })) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden()
            Image(systemName: item.isDirectory ? "folder" : "doc").foregroundStyle(.secondary).font(.iCaption)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).font(.iCallout).lineLimit(1)
                Text(item.url.path).font(.dsMono).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(item.size.formattedBytes).font(.iCallout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var cleanBar: some View {
        HStack(spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Seçili: \(model.totalSelected.formattedBytes)", "Selected: \(model.totalSelected.formattedBytes)")).font(.iHeadline)
                Text(L("Toplam: \(model.totalFound.formattedBytes) • geri alınabilir (Çöp)", "Total: \(model.totalFound.formattedBytes) • recoverable (Trash)")).font(.iCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Yeniden Tara", "Rescan")) { Task { await model.scan() } }.buttonStyle(.glass)
            Button {
                if model.hasRiskySelection { showConfirm = true } else { Task { await model.clean() } }
            } label: {
                Label(L("Çöp'e Taşı", "Move to Trash"), systemImage: "trash").padding(.horizontal, DS.Spacing.s)
            }
            .buttonStyle(.glassProminent).tint(DS.Palette.danger).disabled(model.selectedItems.isEmpty)
        }
        .padding(DS.Spacing.l)
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.l))
        .padding(.horizontal, DS.Spacing.m).padding(.bottom, DS.Spacing.m)
    }

    private var cleaning: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            HStack(spacing: DS.Spacing.m) { ProgressView().controlSize(.large); Text(L("Çöp'e taşınıyor…", "Moving to Trash…")).font(.dsTitle) }
            LiveLogPanel(lines: model.logLines, height: 400)
        }
        .padding(DS.Spacing.xxl)
    }

    private var done: some View {
        VStack(spacing: DS.Spacing.l) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(DS.Palette.safe)
            Text(L("Temizlik tamamlandı", "Cleanup complete")).font(.dsDisplay(32))
            if let r = model.report {
                HStack(spacing: DS.Spacing.m) {
                    StatTile(title: L("Geri kazanılan", "Reclaimed"), value: r.bytesReclaimed.formattedBytes, systemImage: "internaldrive", tint: DS.Palette.safe)
                    StatTile(title: L("Çöp'e taşınan", "Moved to Trash"), value: "\(r.trashedCount)", systemImage: "trash")
                    if r.skippedCount + r.failedCount > 0 {
                        StatTile(title: L("Atlanan/Hata", "Skipped/Error"), value: "\(r.skippedCount + r.failedCount)", systemImage: "exclamationmark.triangle", tint: DS.Palette.caution)
                    }
                }.frame(maxWidth: 640)
            }
            Button(L("Tekrar Tara", "Scan Again")) { Task { await model.scan() } }.buttonStyle(.glassProminent).tint(.accentColor)
            Text(L("Silinenler Çöp Kutusu'nda — geri alabilirsin.", "Deleted items are in the Trash — you can restore them.")).font(.iCaption).foregroundStyle(.tertiary)
        }
        .padding(DS.Spacing.xxl).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
