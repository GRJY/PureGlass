import Foundation

/// Eşzamanlı, iptal edilebilir tarama motoru.
///
/// - Sembolik linkleri TAKİP ETMEZ (güvenlik + döngü koruması).
/// - Diskte ayrılmış gerçek boyutu (`totalFileAllocatedSize`) ölçer → geri kazanılacak alan.
/// - `Task.isCancelled` ile her noktada iptal edilebilir.
/// - İzin yoksa zarif düşüş: o konum `isAccessible == false` ile döner, tarama sürer.
public struct ScanEngine: Sendable {
    public init() {}

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey
    ]

    /// Verilen konumları eşzamanlı tarar; en büyük sonuç önce gelecek şekilde sıralı döner.
    public func scan(
        _ locations: [CleanLocation],
        onProgress: (@Sendable (ScanProgress) async -> Void)? = nil
    ) async -> [CategoryScanResult] {
        let total = locations.count
        var results: [CategoryScanResult] = []
        var completed = 0
        var bytes: Int64 = 0

        await withTaskGroup(of: CategoryScanResult.self) { group in
            for loc in locations {
                group.addTask { self.scanLocation(loc) }
            }
            for await result in group {
                results.append(result)
                completed += 1
                bytes += result.totalSize
                await onProgress?(ScanProgress(
                    completedLocations: completed,
                    totalLocations: total,
                    currentTitle: result.title,
                    bytesFound: bytes
                ))
            }
        }
        return results.sorted { $0.totalSize > $1.totalSize }
    }

    /// Tek bir konumu tarar: kökün üst-düzey çocuklarını öğe olarak listeler, boyutlarını ölçer.
    public func scanLocation(_ location: CleanLocation) -> CategoryScanResult {
        let fm = FileManager.default

        // Var olmayan dizin → erişilebilir ama boş (silinecek bir şey yok).
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: location.url.path, isDirectory: &isDir), isDir.boolValue else {
            return result(location, items: [], accessible: true)
        }

        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: location.url,
                includingPropertiesForKeys: Array(Self.resourceKeys),
                options: []
            )
        } catch {
            // Okunamadı (büyük olasılıkla izin) → erişilemez işaretle.
            return result(location, items: [], accessible: false)
        }

        var items: [FileItem] = []
        for child in entries {
            if Task.isCancelled { break }
            guard let rv = try? child.resourceValues(forKeys: Self.resourceKeys) else { continue }
            if rv.isSymbolicLink == true { continue }  // symlink'leri takip etme

            let directory = rv.isDirectory == true
            let (size, count): (Int64, Int)
            if directory {
                (size, count) = measure(child)
            } else {
                size = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? rv.fileSize ?? 0)
                count = 1
            }
            items.append(FileItem(
                url: child, size: size, isDirectory: directory, fileCount: count,
                modificationDate: rv.contentModificationDate,
                category: location.category, risk: location.risk
            ))
        }
        return result(location, items: items, accessible: true)
    }

    // MARK: - Yardımcılar

    /// Bir dizinin toplam ayrılmış boyutunu ve dosya sayısını özyinelemesiz (stack) hesaplar.
    /// Sembolik linkleri takip etmez.
    private func measure(_ root: URL) -> (bytes: Int64, fileCount: Int) {
        let fm = FileManager.default
        var bytes: Int64 = 0
        var count = 0
        var stack = [root]

        while let dir = stack.popLast() {
            if Task.isCancelled { break }
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: Array(Self.resourceKeys),
                options: []
            ) else { continue }

            for url in entries {
                if Task.isCancelled { break }
                guard let rv = try? url.resourceValues(forKeys: Self.resourceKeys) else { continue }
                if rv.isSymbolicLink == true { continue }
                if rv.isDirectory == true {
                    stack.append(url)
                } else {
                    bytes += Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? rv.fileSize ?? 0)
                    count += 1
                }
            }
        }
        return (bytes, count)
    }

    private func result(_ loc: CleanLocation, items: [FileItem], accessible: Bool) -> CategoryScanResult {
        CategoryScanResult(
            locationID: loc.id, category: loc.category, title: loc.title,
            url: loc.url, risk: loc.risk,
            items: items.sorted { $0.size > $1.size }, isAccessible: accessible
        )
    }
}
