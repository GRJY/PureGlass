import Foundation

/// Bir kabuk komutunu yönetici (root) yetkisiyle çalıştırır.
/// Sistem güvenli kimlik doğrulama penceresi açar (parola sorar). İmzasız uygulamalarda da çalışır.
///
/// NSAppleScript UI gösterdiği için MUTLAKA ana iş parçacığında çağrılmalıdır.
enum AdminShell {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @MainActor
    static func run(_ command: String) throws {
        // AppleScript string literali için kaçış (önce ters bölü, sonra çift tırnak).
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else {
            throw Failure(message: "Yetkili komut hazırlanamadı.")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let msg = (error[NSAppleScript.errorMessage] as? String) ?? "Yetkili komut başarısız oldu."
            throw Failure(message: msg)
        }
    }
}
