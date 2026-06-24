import Foundation

/// Yıkıcı işlemlerin son güvenlik kapısı (backstop).
///
/// Bir yolun silinmesine YALNIZCA şu koşullarda izin verir:
/// 1. Boş veya kök (`/`) değil,
/// 2. Kritik bir dizin değil (ev, /Users, /Library, izinli köklerin kendisi…),
/// 3. Korumalı sistem yolu değil (`/System`, `/usr`, `/bin`…),
/// 4. İzinli köklerden birinin GERÇEK (sembolik link çözülmüş) ALT öğesi,
/// 5. Sembolik link ile izinli kökün dışına kaçmıyor (TOCTOU/symlink koruması).
///
/// Tüm kontroller sembolik linkler çözüldükten sonra gerçek yol üzerinde yapılır.
public struct SafetyGuard: Sendable {
    public enum Violation: Error, Equatable, CustomStringConvertible {
        case empty
        case rootPath
        case criticalPath(String)
        case protectedSystemPath(String)
        case allowedRootItself(String)
        case outsideAllowedRoots(String)
        case symlinkEscape(from: String, to: String)

        public var description: String {
            switch self {
            case .empty: return "Boş yol."
            case .rootPath: return "Kök dizin (/) silinemez."
            case .criticalPath(let p): return "Kritik dizin silinemez: \(p)"
            case .protectedSystemPath(let p): return "Korumalı sistem yolu: \(p)"
            case .allowedRootItself(let p): return "İzinli kökün kendisi silinemez (yalnızca içeriği): \(p)"
            case .outsideAllowedRoots(let p): return "İzinli alanların dışında: \(p)"
            case .symlinkEscape(let from, let to): return "Sembolik link kaçışı: \(from) → \(to)"
            }
        }
    }

    private let allowedRoots: [String]      // çözülmüş + standartlaştırılmış mutlak yollar
    private let protectedPrefixes: [String]
    private let criticalPaths: Set<String>

    public init(
        allowedRoots roots: [URL],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let resolved = roots.map { Self.canonical($0) }
        self.allowedRoots = resolved

        self.protectedPrefixes = [
            "/System", "/bin", "/sbin", "/usr",
            "/Library/Apple", "/Library/Developer/CommandLineTools",
            "/private/var/db", "/private/var/vm",
            "/Applications", "/opt", "/cores", "/Network", "/Volumes"
        ]

        func homeSub(_ sub: String) -> String { Self.canonical(home.appending(path: sub)) }
        var crit: Set<String> = [
            "/", "/Users", "/Library", "/System", "/private", "/private/var",
            "/private/etc", "/etc", "/var", "/tmp",
            Self.canonical(home),
            homeSub("Library"), homeSub("Desktop"), homeSub("Documents"),
            homeSub("Downloads"), homeSub("Pictures"), homeSub("Movies"),
            homeSub("Music"), homeSub("Public")
        ]
        crit.formUnion(resolved)   // izinli köklerin kendileri de asla silinmez
        self.criticalPaths = crit
    }

    /// Konum veritabanındaki tüm köklerden bir koruyucu üretir.
    public init(
        database: LocationsDatabase,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.init(allowedRoots: database.locations.map(\.url), home: home)
    }

    /// Sembolik linkleri çözüp standartlaştırılmış mutlak yol döndürür.
    static func canonical(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Yol silinemezse uygun `Violation` fırlatır.
    ///
    /// `/var` → `/private/var` gibi sistem symlink'lerine karşı sağlam olmak için:
    /// ebeveyn dizini canonical'lenir (parent symlink'leri çözülür), öğenin adı
    /// eklenir → "amaçlanan" canonical yol. Tüm yapısal kontroller bunun üzerinde
    /// yapılır. Öğenin KENDİSİ bir symlink ise gerçek hedefi ayrıca kontrol edilir.
    public func validate(_ url: URL) throws {
        let std = url.standardizedFileURL.path
        guard !std.isEmpty else { throw Violation.empty }
        if std == "/" { throw Violation.rootPath }

        let lastComponent = url.lastPathComponent
        let realParent = Self.canonical(url.deletingLastPathComponent())
        let intended = (realParent as NSString).appendingPathComponent(lastComponent)

        if intended == "/" { throw Violation.rootPath }

        // 1) kritik / izinli kökün kendisi
        if criticalPaths.contains(intended) {
            if allowedRoots.contains(intended) { throw Violation.allowedRootItself(intended) }
            throw Violation.criticalPath(intended)
        }

        // 2) korumalı sistem yolu
        for p in protectedPrefixes where intended == p || intended.hasPrefix(p + "/") {
            throw Violation.protectedSystemPath(intended)
        }

        // 3) amaçlanan yol izinli bir kökün ALT öğesi olmalı
        let intendedInside = allowedRoots.contains { intended.hasPrefix($0 + "/") }
        guard intendedInside else { throw Violation.outsideAllowedRoots(intended) }

        // 4) öğenin kendisi symlink ise gerçek hedef de güvenli olmalı.
        //    (Tam yolu yalnızca gerçek symlink'lerde canonical'liyoruz; var olmayan
        //     yollarda macOS firmlink kısaltması tutarsız davrandığı için.)
        let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
        if isSymlink {
            let realSelf = Self.canonical(url)
            if realSelf != intended {
                for p in protectedPrefixes where realSelf == p || realSelf.hasPrefix(p + "/") {
                    throw Violation.protectedSystemPath(realSelf)
                }
                let realInside = allowedRoots.contains { realSelf == $0 || realSelf.hasPrefix($0 + "/") }
                if !realInside { throw Violation.symlinkEscape(from: intended, to: realSelf) }
            }
        }
    }

    public func isValid(_ url: URL) -> Bool {
        (try? validate(url)) != nil
    }
}
