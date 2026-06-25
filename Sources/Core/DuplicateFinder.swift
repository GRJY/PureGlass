import Foundation
import CryptoKit

/// İçerikleri aynı olan dosya grubu.
public struct DuplicateGroup: Identifiable, Sendable, Hashable {
    public var id: String { hash }
    public let hash: String
    public let size: Int64        // dosya başına boyut
    public let urls: [URL]

    /// Bir kopya tutulup gerisi silinirse kazanılacak alan.
    public var wastedBytes: Int64 { size * Int64(max(0, urls.count - 1)) }

    public init(hash: String, size: Int64, urls: [URL]) {
        self.hash = hash
        self.size = size
        self.urls = urls
    }
}

/// Yinelenen dosyaları içerik karması (SHA-256) ile bulur.
/// Önce boyuta göre eler (aynı boyut olmayan dosya kopya olamaz), sonra çakışan
/// boyut gruplarını karmalar → I/O'yu en aza indirir.
public struct DuplicateFinder: Sendable {
    public init() {}

    public func find(in roots: [URL], minSize: Int64 = 4096) async -> [DuplicateGroup] {
        // 1) Tüm dosyaları boyuta göre topla (senkron enumerator).
        let bySize = Self.collectBySize(roots: roots, minSize: minSize)

        // 2) Yalnızca aynı boyutta birden fazla dosya olan adaylar.
        let candidates = bySize.filter { $0.value.count > 1 }

        // 3) Adayları eşzamanlı karmala.
        var byHash: [String: (size: Int64, urls: [URL])] = [:]
        await withTaskGroup(of: (hash: String, size: Int64, url: URL)?.self) { group in
            for (size, urls) in candidates {
                for url in urls {
                    group.addTask {
                        guard let h = Self.hash(url) else { return nil }
                        return (h, size, url)
                    }
                }
            }
            for await result in group {
                if let r = result {
                    byHash[r.hash, default: (r.size, [])].urls.append(r.url)
                    byHash[r.hash]?.size = r.size
                }
            }
        }

        // 4) Aynı karma + >1 dosya = yinelenen.
        let groups: [DuplicateGroup] = byHash.compactMap { key, value in
            guard value.urls.count > 1 else { return nil }
            return DuplicateGroup(hash: key, size: value.size,
                                  urls: value.urls.sorted { $0.path < $1.path })
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    static func collectBySize(roots: [URL], minSize: Int64) -> [Int64: [URL]] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var bySize: [Int64: [URL]] = [:]
        for root in roots {
            guard let en = fm.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in en {
                if Task.isCancelled { return bySize }
                guard let rv = try? url.resourceValues(forKeys: keys) else { continue }
                if rv.isSymbolicLink == true || rv.isRegularFile != true { continue }
                let size = Int64(rv.fileSize ?? 0)
                if size < minSize { continue }
                bySize[size, default: []].append(url)
            }
        }
        return bySize
    }

    static func hash(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var hasher = SHA256()
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
