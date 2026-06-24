import Foundation

/// Full Disk Access (Tam Disk Erişimi) durumunu tespit eder.
///
/// FDA bir entitlement DEĞİLDİR; kullanıcı elle Sistem Ayarları'ndan verir.
/// Tespit için TCC-korumalı bir kaynağı okumayı deneriz: okunabiliyorsa FDA var.
public struct FullDiskAccess: Sendable {
    public enum Status: Sendable, Equatable {
        case granted
        case denied
        case unknown   // prob kaynakları bulunamadı; kesin karar verilemiyor
    }

    let probePaths: [URL]

    public init(
        probePaths: [URL]? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.probePaths = probePaths ?? [
            home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db"),
            URL(filePath: "/Library/Application Support/com.apple.TCC/TCC.db"),
            home.appending(path: "Library/Safari/CloudTabs.db")
        ]
    }

    /// Korumalı kaynaklardan biri okunabiliyorsa `.granted`; varlar ama hiçbiri
    /// okunamıyorsa `.denied`; hiç prob yoksa `.unknown`.
    public func currentStatus() -> Status {
        var sawProbe = false
        for url in probePaths where FileManager.default.fileExists(atPath: url.path) {
            sawProbe = true
            if canRead(url) { return .granted }
        }
        return sawProbe ? .denied : .unknown
    }

    func canRead(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        try? handle.close()
        return true
    }

    /// Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi panelini açan URL.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )!
}
