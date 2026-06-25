import Foundation

/// Disk haritasındaki tek bir öğe (bir dizinin/dosyanın özyinelemeli boyutu).
public struct DiskMapEntry: Identifiable, Sendable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let size: Int64
    public let isDirectory: Bool
    public let fileCount: Int

    public init(url: URL, name: String, size: Int64, isDirectory: Bool, fileCount: Int) {
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.fileCount = fileCount
    }
}

/// Bir dizinin doğrudan çocuklarını, her birinin özyinelemeli (allocated) boyutuyla hesaplar.
/// Drill-down treemap için tasarlandı: her seferinde tek bir seviye, çocuklar eşzamanlı ölçülür.
public struct DiskMapScanner: Sendable {
    public init() {}

    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey
    ]

    /// `directory`'nin doğrudan çocukları, boyuta göre azalan sıralı. Symlink'ler atlanır.
    public func children(of directory: URL) async -> [DiskMapEntry] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(Self.keys),
            options: []
        ) else { return [] }

        let candidates = entries.filter {
            (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        }

        return await withTaskGroup(of: DiskMapEntry?.self) { group in
            for url in candidates {
                group.addTask { self.entry(for: url) }
            }
            var result: [DiskMapEntry] = []
            for await entry in group {
                if let entry { result.append(entry) }
            }
            return result.sorted { $0.size > $1.size }
        }
    }

    func entry(for url: URL) -> DiskMapEntry? {
        guard let rv = try? url.resourceValues(forKeys: Self.keys) else { return nil }
        if rv.isDirectory == true {
            let (bytes, count) = measure(url)
            return DiskMapEntry(url: url, name: url.lastPathComponent, size: bytes, isDirectory: true, fileCount: count)
        } else {
            let bytes = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? rv.fileSize ?? 0)
            return DiskMapEntry(url: url, name: url.lastPathComponent, size: bytes, isDirectory: false, fileCount: 1)
        }
    }

    /// Bir dizinin toplam ayrılmış boyutu + dosya sayısı (özyinelemesiz stack, symlink takip etmez).
    private func measure(_ root: URL) -> (bytes: Int64, fileCount: Int) {
        let fm = FileManager.default
        var bytes: Int64 = 0
        var count = 0
        var stack = [root]
        while let dir = stack.popLast() {
            if Task.isCancelled { break }
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: Array(Self.keys), options: []
            ) else { continue }
            for url in entries {
                guard let rv = try? url.resourceValues(forKeys: Self.keys) else { continue }
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
}
