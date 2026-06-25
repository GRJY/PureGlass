import Foundation

/// Fan kontrolü: paketlenmiş `pgsmc` root yardımcısını `AdminShell` (yönetici parolası) ile
/// çalıştırır. Yalnızca M1/M2'de sunulur.
enum FanController {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Contents/MacOS/pgsmc
    static var helperURL: URL? {
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("pgsmc")
    }

    @MainActor
    static func setManual(rpm: Int) throws {
        guard let h = helperURL, FileManager.default.fileExists(atPath: h.path) else {
            throw Failure(message: "Yardımcı bileşen (pgsmc) bulunamadı.")
        }
        try AdminShell.run("'\(h.path)' set \(rpm)")
    }

    @MainActor
    static func setAuto() throws {
        guard let h = helperURL, FileManager.default.fileExists(atPath: h.path) else {
            throw Failure(message: "Yardımcı bileşen (pgsmc) bulunamadı.")
        }
        try AdminShell.run("'\(h.path)' auto")
    }
}
