import Foundation

/// Time Machine yerel APFS anlık görüntüleri (local snapshots).
/// L("Sistem Verileri", "System Data")nin en büyük gizli bileşeni; DOSYA DEĞİLDİR (APFS snapshot),
/// bu yüzden dosya taramasıyla görülemez — `tmutil` ile yönetilir.
enum TimeMachineService {
    /// `/` üzerindeki yerel snapshot adlarını döndürür (örn. 2026-06-25-104512).
    static func localSnapshotDates() -> [String] {
        let output = runCapture("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("com.apple.TimeMachine") }
            .compactMap { line in
                // com.apple.TimeMachine.2026-06-25-104512.local → 2026-06-25-104512
                let parts = line.split(separator: ".")
                guard parts.count >= 4 else { return nil }
                return String(parts[3])
            }
    }

    /// Tüm yerel snapshot'ları siler (tek yönetici parolası istemiyle).
    /// `tmutil deletelocalsnapshots` ayrıcalık gerektirir.
    @MainActor
    static func deleteAllLocalSnapshots() throws {
        let dates = localSnapshotDates()
        guard !dates.isEmpty else { return }
        let cmd = dates.map { "/usr/bin/tmutil deletelocalsnapshots \($0)" }.joined(separator: " ; ")
        try AdminShell.run(cmd)
    }

    private static func runCapture(_ launchPath: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(filePath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
