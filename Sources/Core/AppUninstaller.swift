import Foundation

/// Kurulu bir uygulama.
public struct InstalledApp: Identifiable, Sendable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let size: Int64
    public let isAppleApp: Bool

    public init(url: URL, name: String, bundleID: String?, size: Int64, isAppleApp: Bool) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.size = size
        self.isAppleApp = isAppleApp
    }
}

/// `/Applications` ve `~/Applications` içindeki uygulamaları bulur.
public struct AppFinder: Sendable {
    public init() {}

    public func defaultDirectories(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [URL(filePath: "/Applications"),
         URL(filePath: "/Applications/Utilities"),
         home.appending(path: "Applications")]
    }

    public func installedApps(
        in directories: [URL]? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async -> [InstalledApp] {
        let dirs = directories ?? defaultDirectories(home: home)
        let fm = FileManager.default
        var appURLs: [URL] = []
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }
            appURLs += entries.filter { $0.pathExtension == "app" }
        }

        return await withTaskGroup(of: InstalledApp?.self) { group in
            for url in appURLs {
                group.addTask { self.app(at: url) }
            }
            var result: [InstalledApp] = []
            for await app in group { if let app { result.append(app) } }
            return result.sorted { $0.size > $1.size }
        }
    }

    func app(at url: URL) -> InstalledApp? {
        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier
        let name = (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let (size, _) = measure(url)
        let isApple = bundleID?.hasPrefix("com.apple.") ?? false
        return InstalledApp(url: url, name: name, bundleID: bundleID, size: size, isAppleApp: isApple)
    }

    private func measure(_ root: URL) -> (Int64, Int) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        var bytes: Int64 = 0, count = 0
        var stack = [root]
        while let dir = stack.popLast() {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: []) else { continue }
            for url in entries {
                guard let rv = try? url.resourceValues(forKeys: keys) else { continue }
                if rv.isSymbolicLink == true { continue }
                if rv.isDirectory == true { stack.append(url) }
                else { bytes += Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? rv.fileSize ?? 0); count += 1 }
            }
        }
        return (bytes, count)
    }
}

/// Bir uygulamanın sistemdeki artıklarını (cache, prefs, container, log…) bulur.
/// Eşleştirme öncelikle bundle ID ile (kesin), ek olarak uygulama adıyla yapılır.
public struct AppLeftoverFinder: Sendable {
    let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Yalnızca DİSKTE VAR OLAN artık yollarını döndürür (boyutlarıyla).
    public func leftovers(for app: InstalledApp) -> [DiskMapEntry] {
        let lib = home.appending(path: "Library")
        var candidates: [URL] = []

        if let bid = app.bundleID, !bid.isEmpty {
            candidates += [
                lib.appending(path: "Caches/\(bid)"),
                lib.appending(path: "Preferences/\(bid).plist"),
                lib.appending(path: "Containers/\(bid)"),
                lib.appending(path: "Saved Application State/\(bid).savedState"),
                lib.appending(path: "HTTPStorages/\(bid)"),
                lib.appending(path: "WebKit/\(bid)"),
                lib.appending(path: "Application Scripts/\(bid)"),
                lib.appending(path: "Application Support/\(bid)"),
                lib.appending(path: "Logs/\(bid)"),
                lib.appending(path: "Cookies/\(bid).binarycookies"),
            ]
            candidates += groupContainers(matching: bid, in: lib)
        }
        // Ada göre (bundle ID dışı uygulamalar için).
        candidates += [
            lib.appending(path: "Application Support/\(app.name)"),
            lib.appending(path: "Logs/\(app.name)"),
            lib.appending(path: "Caches/\(app.name)"),
        ]

        let fm = FileManager.default
        var seen = Set<String>()
        var result: [DiskMapEntry] = []
        for url in candidates where fm.fileExists(atPath: url.path) {
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            let size = entrySize(url, isDirectory: isDir.boolValue)
            result.append(DiskMapEntry(url: url, name: url.lastPathComponent, size: size,
                                       isDirectory: isDir.boolValue, fileCount: 1))
        }
        return result.sorted { $0.size > $1.size }
    }

    private func groupContainers(matching bid: String, in lib: URL) -> [URL] {
        let gc = lib.appending(path: "Group Containers")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: gc, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        // Grup container adları genelde "<teamID>.<bid>" biçimindedir.
        return entries.filter { $0.lastPathComponent.contains(bid) }
    }

    private func entrySize(_ url: URL, isDirectory: Bool) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        if !isDirectory {
            let rv = try? url.resourceValues(forKeys: keys)
            return Int64(rv?.totalFileAllocatedSize ?? rv?.fileAllocatedSize ?? rv?.fileSize ?? 0)
        }
        let fm = FileManager.default
        var bytes: Int64 = 0
        var stack = [url]
        while let dir = stack.popLast() {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys) + [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { continue }
            for u in entries {
                guard let rv = try? u.resourceValues(forKeys: keys.union([.isDirectoryKey, .isSymbolicLinkKey])) else { continue }
                if rv.isSymbolicLink == true { continue }
                if rv.isDirectory == true { stack.append(u) }
                else { bytes += Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? rv.fileSize ?? 0) }
            }
        }
        return bytes
    }
}
