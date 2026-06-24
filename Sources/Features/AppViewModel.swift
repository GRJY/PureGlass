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

    var phase: Phase = .idle
    var results: [CategoryScanResult] = []
    var selectedURLs: Set<URL> = []
    var scanProgress: Double = 0
    var scanStatusText = ""
    var logLines: [LogLine] = []
    var report: CleanReport?

    init() {
        cleaningEngine = CleaningEngine(safety: SafetyGuard(database: database))
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

        let locations = database.userSpaceLocations
        let scanned = await scanEngine.scan(locations) { [weak self] progress in
            await MainActor.run {
                self?.scanProgress = progress.fraction
                self?.scanStatusText = progress.currentTitle
            }
        }

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
        let items = selectedItems
        let finalReport = await cleaningEngine.clean(items) { [weak self] event in
            await MainActor.run {
                self?.logLines.append(LogLine(event: event))
            }
        }
        report = finalReport
        phase = .done
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
