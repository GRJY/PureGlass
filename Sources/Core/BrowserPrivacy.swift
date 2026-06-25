import Foundation

/// Bir tarayıcının silinebilir gizlilik verisi (önbellek/geçmiş/çerez).
public struct BrowserPrivacyItem: Identifiable, Sendable, Hashable {
    public var id: URL { url }
    public let browser: String
    public let kind: String        // "Önbellek" / "Geçmiş" / "Çerezler"
    public let url: URL
    public let size: Int64
    public let isDirectory: Bool

    public init(browser: String, kind: String, url: URL, size: Int64, isDirectory: Bool) {
        self.browser = browser
        self.kind = kind
        self.url = url
        self.size = size
        self.isDirectory = isDirectory
    }
}

/// Yaygın tarayıcıların gizlilik verisini (var olanları, boyutlarıyla) bulur.
public struct BrowserPrivacyScanner: Sendable {
    let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func scan() -> [BrowserPrivacyItem] {
        let lib = home.appending(path: "Library")
        let appSup = lib.appending(path: "Application Support")
        var defs: [(String, String, URL)] = [
            ("Safari", "Önbellek", lib.appending(path: "Caches/com.apple.Safari")),
            ("Safari", "Önbellek", lib.appending(path: "Containers/com.apple.Safari/Data/Library/Caches")),
            ("Chrome", "Önbellek", appSup.appending(path: "Google/Chrome/Default/Cache")),
            ("Chrome", "Geçmiş", appSup.appending(path: "Google/Chrome/Default/History")),
            ("Chrome", "Çerezler", appSup.appending(path: "Google/Chrome/Default/Cookies")),
            ("Brave", "Önbellek", appSup.appending(path: "BraveSoftware/Brave-Browser/Default/Cache")),
            ("Edge", "Önbellek", appSup.appending(path: "Microsoft Edge/Default/Cache")),
        ]
        // Firefox profilleri (joker)
        let ffProfiles = appSup.appending(path: "Firefox/Profiles")
        if let profs = try? FileManager.default.contentsOfDirectory(at: ffProfiles, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for p in profs {
                defs.append(("Firefox", "Önbellek", p.appending(path: "cache2")))
                defs.append(("Firefox", "Geçmiş", p.appending(path: "places.sqlite")))
                defs.append(("Firefox", "Çerezler", p.appending(path: "cookies.sqlite")))
            }
        }

        let fm = FileManager.default
        var result: [BrowserPrivacyItem] = []
        for (browser, kind, url) in defs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let size = Self.measure(url, isDirectory: isDir.boolValue)
            result.append(BrowserPrivacyItem(browser: browser, kind: kind, url: url, size: size, isDirectory: isDir.boolValue))
        }
        return result.sorted { $0.size > $1.size }
    }

    static func measure(_ url: URL, isDirectory: Bool) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        if !isDirectory {
            let rv = try? url.resourceValues(forKeys: keys)
            return Int64(rv?.totalFileAllocatedSize ?? rv?.fileAllocatedSize ?? rv?.fileSize ?? 0)
        }
        let fm = FileManager.default
        var bytes: Int64 = 0
        var stack = [url]
        while let dir = stack.popLast() {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: []) else { continue }
            for u in entries {
                guard let rv = try? u.resourceValues(forKeys: keys) else { continue }
                if rv.isSymbolicLink == true { continue }
                if rv.isDirectory == true { stack.append(u) }
                else { bytes += Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? rv.fileSize ?? 0) }
            }
        }
        return bytes
    }
}
