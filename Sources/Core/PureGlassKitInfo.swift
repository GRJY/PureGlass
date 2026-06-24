import Foundation

/// PureGlassKit çekirdek modülü hakkında temel bilgi.
///
/// İleriki fazlarda bu modül şunları barındıracak:
/// - `LocationsDatabase` (FAZ 2) — kategorize, risk seviyeli güvenli yollar
/// - `SafetyGuard` (FAZ 2) — blocklist + safe-root + symlink/TOCTOU koruması
/// - `ScanEngine` (FAZ 3) — eşzamanlı tarama
/// - `CleaningEngine` (FAZ 5) — trash-first silme
/// - `PermissionCoordinator` (FAZ 4) — Full Disk Access
public enum PureGlassKitInfo {
    public static let version = "0.1.0"
    public static let name = "PureGlassKit"
}
