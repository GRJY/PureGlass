import Foundation
import Observation
import PureGlassKit

/// Uygulamanın ana durum yöneticisi: tarama, seçim, temizlik ve izin akışını birleştirir.
@MainActor
@Observable
final class AppViewModel {
    enum Phase: Equatable {
        case idle, scanning, results, cleaning, done
    }

    let database = LocationsDatabase()
    let scanEngine = ScanEngine()
    let permissions = PermissionCoordinator()
    private let cleaningEngine: CleaningEngine
    private let privilegedCleaner: PrivilegedCleaner

    var phase: Phase = .idle
    var results: [CategoryScanResult] = []
    var selectedURLs: Set<URL> = []
    var scanProgress: Double = 0
    var scanStatusText = ""
    var scanBytesFound: Int64 = 0
    var lockedCategories = 0
    var logLines: [LogLine] = []
    var report: CleanReport?

    /// Derin sistem temizliği (root öğeleri de tarar/temizler; yönetici parolası gerekir).
    var deepClean = false

    init() {
        cleaningEngine = CleaningEngine(safety: SafetyGuard(database: database))
        privilegedCleaner = PrivilegedCleaner(database: database)
    }

    // MARK: - Türetilmiş değerler

    var allItems: [FileItem] { results.flatMap(\.items) }

    var selectedItems: [FileItem] { allItems.filter { selectedURLs.contains($0.url) } }

    var totalFoundSize: Int64 { results.reduce(0) { $0 + $1.totalSize } }

    var totalSelectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    func isSelected(_ item: FileItem) -> Bool { selectedURLs.contains(item.url) }

    func toggle(_ item: FileItem) {
        if selectedURLs.contains(item.url) { selectedURLs.remove(item.url) }
        else { selectedURLs.insert(item.url) }
    }

    func toggleCategory(_ result: CategoryScanResult) {
        let urls = result.items.map(\.url)
        if urls.allSatisfy(selectedURLs.contains) {
            urls.forEach { selectedURLs.remove($0) }
        } else {
            urls.forEach { selectedURLs.insert($0) }
        }
    }

    func selectionState(of result: CategoryScanResult) -> Bool {
        !result.items.isEmpty && result.items.allSatisfy { selectedURLs.contains($0.url) }
    }

    // MARK: - Eylemler

    func scan() async {
        phase = .scanning
        results = []
        selectedURLs = []
        logLines = []
        report = nil
        scanProgress = 0
        scanStatusText = "Başlatılıyor…"

        let locations = deepClean ? database.locations : database.userSpaceLocations
        let scanned = await scanEngine.scan(locations) { [weak self] progress in
            await MainActor.run {
                self?.scanProgress = progress.fraction
                self?.scanStatusText = progress.currentTitle
                self?.scanBytesFound = progress.bytesFound
            }
        }

        lockedCategories = scanned.filter { !$0.isAccessible }.count
        results = scanned.filter { $0.isAccessible && !$0.items.isEmpty }
        // Güvenli (yeşil) öğeleri önceden seç.
        for result in results where result.risk == .safe {
            result.items.forEach { selectedURLs.insert($0.url) }
        }
        phase = .results
    }

    func clean() async {
        guard !selectedItems.isEmpty else { return }
        phase = .cleaning
        logLines = []

        let rootItems = selectedItems.filter(\.requiresRoot)
        let userItems = selectedItems.filter { !$0.requiresRoot }

        // 1) Kullanıcı alanı → Çöp'e (trash-first).
        let userReport = await cleaningEngine.clean(userItems) { [weak self] event in
            await MainActor.run { self?.logLines.append(LogLine(event: event)) }
        }
        var events = userReport.events

        // 2) Sistem (root) öğeleri → tek yönetici parolası istemiyle kalıcı sil.
        if !rootItems.isEmpty {
            events += await cleanPrivileged(rootItems)
        }

        report = CleanReport(events: events)
        phase = .done
    }

    /// Root öğelerini doğrular, tek bir yetkili komutla siler, olayları döndürür.
    private func cleanPrivileged(_ items: [FileItem]) async -> [CleanEvent] {
        let (valid, skipped) = privilegedCleaner.partition(items)
        var events: [CleanEvent] = skipped.map {
            CleanEvent(url: $0.url, size: $0.size, outcome: .skippedUnsafe("Sistem güvenli alanı dışında"))
        }
        skipped.forEach { logLines.append(LogLine(event: CleanEvent(url: $0.url, size: $0.size, outcome: .skippedUnsafe("güvensiz")))) }

        guard let command = privilegedCleaner.buildCommand(for: valid.map(\.url)) else { return events }
        do {
            try AdminShell.run(command)   // @MainActor — parola istemi
            for item in valid {
                let e = CleanEvent(url: item.url, size: item.size, outcome: .trashed)
                events.append(e)
                logLines.append(LogLine(event: e))
            }
        } catch {
            for item in valid {
                let e = CleanEvent(url: item.url, size: item.size, outcome: .failed(error.localizedDescription))
                events.append(e)
                logLines.append(LogLine(event: e))
            }
        }
        return events
    }

    func reset() {
        phase = .idle
        results = []
        selectedURLs = []
        logLines = []
        report = nil
        scanProgress = 0
    }
}
