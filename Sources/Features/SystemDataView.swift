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
    var progress: Double = 0
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
        ("Sistem Çerçeveleri", "/System/Library/Frameworks"),
        ("Özel Sistem Çerçeveleri", "/System/Library/PrivateFrameworks"),
        ("Yerleşik Uygulamalar", "/System/Applications"),
        ("Sistem Veritabanları", "/private/var/db"),
        ("Sistem Kütüphaneleri", "/usr/lib"),
        ("Apple Sistem İçeriği", "/Library/Apple"),
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
        progress = 0; bytesFound = 0; statusText = "Başlatılıyor…"
        let scanned = await scanEngine.scan(database.systemData) { [weak self] p in
            await MainActor.run { self?.progress = p.fraction; self?.statusText = p.currentTitle; self?.bytesFound = p.bytesFound }
        }
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
        var events = skipped.map { CleanEvent(url: $0.url, size: $0.size, outcome: .skippedUnsafe("güvensiz")) }
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
        .task { model.refreshSnapshots() }
    }

    /// Time Machine yerel anlık görüntüleri — "Sistem Verileri"nin en büyük gizli bileşeni.
    @ViewBuilder
    private var snapshotCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                HStack {
                    Label("Time Machine Anlık Görüntüleri", systemImage: "clock.arrow.2.circlepath")
                        .font(.dsTitle)
                    Spacer()
                    Text("\(model.snapshotCount) adet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.snapshotCount > 0 ? DS.Palette.caution : DS.Palette.safe)
                }
                Text("Time Machine'in Mac'ine geçici olarak kaydettiği yedek kopyalar. Genellikle \"Sistem Verileri\"nin en büyük parçasıdır ama normal dosya gibi görünmedikleri için listede çıkmazlar. macOS bunları 24 saat içinde kendisi siler; istersen şimdi temizleyebilirsin — tamamen güvenlidir, zaten boş alan olarak sayılırlar.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.snapshotCount > 0 {
                    Button {
                        Task { await model.deleteSnapshots() }
                    } label: {
                        Label(model.snapshotBusy ? "Siliniyor…" : "Anlık Görüntüleri Sil",
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
                Text("Sistem Verileri").font(.dsDisplay(38))
                Text("Mac'inin Depolama ekranında gördüğün, onlarca GB yer kaplayan o gizemli \"Sistem Verileri\"nin içinde tam olarak ne var — gösterir.\nUygulama verileri, önbellekler, iOS yedekleri, geliştirici dosyaları…\n\nHer öğenin yanında renkli bir güvenlik rozeti vardır. Hiçbiri otomatik seçilmez; neyi sileceğine sen karar verirsin.")
                    .font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                GlassCard {
                    HStack(spacing: DS.Spacing.m) {
                        RiskBadge(level: .safe); Text("güvenle silinir").font(.caption).foregroundStyle(.secondary)
                        RiskBadge(level: .caution); Text("dikkatli").font(.caption).foregroundStyle(.secondary)
                        RiskBadge(level: .danger); Text("veri kaybı olabilir").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 560)
                snapshotCard
                Button { Task { await model.scan() } } label: {
                    Label("Dosya-tabanlı Sistem Verilerini Tara", systemImage: "magnifyingglass")
                        .font(.title3.weight(.semibold)).padding(.horizontal, DS.Spacing.l).padding(.vertical, DS.Spacing.s)
                }
                .buttonStyle(.glassProminent).tint(.accentColor).controlSize(.extraLarge)
            }
            .padding(DS.Spacing.xxl).frame(maxWidth: .infinity)
        }
    }

    private var scanning: some View {
        VStack(spacing: DS.Spacing.l) {
            ProgressRing(progress: model.progress, size: 140, animating: true)
            Text("Sistem verileri taranıyor…").font(.dsTitle)
            Text(model.statusText).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Text("\(model.bytesFound.formattedBytes) bulundu").font(.headline.monospacedDigit()).foregroundStyle(.tint)
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
        .alert("Bu işlem geri alınamayabilir", isPresented: $showConfirm) {
            Button("Sil", role: .destructive) { Task { await model.clean() } }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Seçiminde riskli (sarı/kırmızı) öğeler var. Kırmızı sistem öğeleri KALICI silinir ve geri alınamaz. Silmek istediğine emin misin?")
        }
    }

    /// Read-only: macOS'un silinemeyen korumalı alanları (yanında boyut).
    @ViewBuilder
    private var protectedSection: some View {
        Section {
            if model.protectedLoading && model.protectedResults.isEmpty {
                HStack(spacing: DS.Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text("Korumalı alan hesaplanıyor…").font(.callout).foregroundStyle(.secondary)
                }
            }
            ForEach(model.protectedResults) { p in
                HStack(spacing: DS.Spacing.s) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).font(.caption).frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.callout)
                        Text(p.url.path).font(.dsMono).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(p.size.formattedBytes).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                Text("Silinemez Sistem Verileri").font(.headline)
                Text("macOS gerektirir").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if model.protectedTotal > 0 {
                    Text(model.protectedTotal.formattedBytes).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
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
            Text(result.title).font(.headline)
            RiskBadge(level: result.risk)
            Spacer()
            Text(result.totalSize.formattedBytes).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private func itemRow(_ item: FileItem) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Toggle(isOn: Binding(get: { model.isSelected(item) }, set: { _ in model.toggle(item) })) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden()
            Image(systemName: item.isDirectory ? "folder" : "doc").foregroundStyle(.secondary).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).font(.callout).lineLimit(1)
                Text(item.url.path).font(.dsMono).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(item.size.formattedBytes).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var cleanBar: some View {
        HStack(spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Seçili: \(model.totalSelected.formattedBytes)").font(.headline)
                Text("Toplam: \(model.totalFound.formattedBytes) • geri alınabilir (Çöp)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Yeniden Tara") { Task { await model.scan() } }.buttonStyle(.glass)
            Button {
                if model.hasRiskySelection { showConfirm = true } else { Task { await model.clean() } }
            } label: {
                Label("Çöp'e Taşı", systemImage: "trash").padding(.horizontal, DS.Spacing.s)
            }
            .buttonStyle(.glassProminent).tint(DS.Palette.danger).disabled(model.selectedItems.isEmpty)
        }
        .padding(DS.Spacing.l)
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.l))
        .padding(.horizontal, DS.Spacing.m).padding(.bottom, DS.Spacing.m)
    }

    private var cleaning: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            HStack(spacing: DS.Spacing.m) { ProgressView().controlSize(.large); Text("Çöp'e taşınıyor…").font(.dsTitle) }
            LiveLogPanel(lines: model.logLines, height: 400)
        }
        .padding(DS.Spacing.xxl)
    }

    private var done: some View {
        VStack(spacing: DS.Spacing.l) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(DS.Palette.safe)
            Text("Temizlik tamamlandı").font(.dsDisplay(32))
            if let r = model.report {
                HStack(spacing: DS.Spacing.m) {
                    StatTile(title: "Geri kazanılan", value: r.bytesReclaimed.formattedBytes, systemImage: "internaldrive", tint: DS.Palette.safe)
                    StatTile(title: "Çöp'e taşınan", value: "\(r.trashedCount)", systemImage: "trash")
                    if r.skippedCount + r.failedCount > 0 {
                        StatTile(title: "Atlanan/Hata", value: "\(r.skippedCount + r.failedCount)", systemImage: "exclamationmark.triangle", tint: DS.Palette.caution)
                    }
                }.frame(maxWidth: 640)
            }
            Button("Tekrar Tara") { Task { await model.scan() } }.buttonStyle(.glassProminent).tint(.accentColor)
            Text("Silinenler Çöp Kutusu'nda — geri alabilirsin.").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(DS.Spacing.xxl).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
