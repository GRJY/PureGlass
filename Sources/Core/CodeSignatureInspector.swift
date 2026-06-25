import Foundation
import Security

/// Bir çalıştırılabilir dosyanın kod imzası durumu.
public enum SigningStatus: String, Sendable {
    case apple          // Apple imzalı (işletim sistemi bileşeni)
    case developerID    // Developer ID (notarize edilebilir 3. parti) — güvenilir
    case signed         // imzalı ama Apple/Developer ID değil (örn. kurumsal)
    case adhoc          // ad-hoc imza (kimlik yok) — kalıcı görevde şüpheli
    case unsigned       // imzasız — şüpheli
    case invalid        // imza var ama bozuk/geçersiz — zararlı işareti
    case missing        // dosya yok / okunamıyor

    public var isTrusted: Bool { self == .apple || self == .developerID || self == .signed }
}

/// Apple Security framework ile yerinde (offline, ağsız) kod imzası doğrulaması.
/// KnockKnock'ın `Signing.m` yaklaşımının Swift karşılığı.
public struct CodeSignatureInspector: Sendable {
    public init() {}

    public func status(of url: URL) -> SigningStatus {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return .unsigned
        }

        // Temel doğrulama (ağ/notarization sorgusu yok → hızlı, offline).
        let validity = SecStaticCodeCheckValidity(code, [], nil)
        if validity == errSecCSUnsigned { return .unsigned }
        if validity != errSecSuccess { return .invalid }

        // Ad-hoc imza bayrağı?
        var infoCF: CFDictionary?
        if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
           let info = infoCF as? [String: Any],
           let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value {
            let adhocFlag: UInt32 = 0x2   // kSecCodeSignatureAdhoc
            if flags & adhocFlag != 0 { return .adhoc }
        }

        if matches(code, "anchor apple") { return .apple }
        if matches(code, "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists") {
            return .developerID
        }
        return .signed
    }

    private func matches(_ code: SecStaticCode, _ requirement: String) -> Bool {
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess,
              let req else { return false }
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
}
