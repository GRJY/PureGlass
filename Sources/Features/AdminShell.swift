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
            throw Failure(message: L("Yetkili komut hazırlanamadı.", "Could not prepare the privileged command."))
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let msg = (error[NSAppleScript.errorMessage] as? String) ?? L("Yetkili komut başarısız oldu.", "The privileged command failed.")
            throw Failure(message: msg)
        }
    }
}
