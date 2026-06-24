import Foundation
import Observation

/// Full Disk Access izin akışının tek yönetim noktası:
/// durum tespiti, Ayarlar'a yönlendirme, izin verilince otomatik yakalama (polling).
@MainActor
@Observable
public final class PermissionCoordinator {
    public private(set) var status: FullDiskAccess.Status

    private let fda: FullDiskAccess
    private var pollTask: Task<Void, Never>?

    /// İzin verildiği anda tetiklenir (UI'ın kilitli kategorileri açması için).
    public var onGranted: (@MainActor () -> Void)?

    public init(fda: FullDiskAccess = FullDiskAccess()) {
        self.fda = fda
        self.status = fda.currentStatus()
    }

    public var settingsURL: URL { FullDiskAccess.settingsURL }
    public var isGranted: Bool { status == .granted }

    /// Durumu yeniden ölç.
    @discardableResult
    public func refresh() -> FullDiskAccess.Status {
        status = fda.currentStatus()
        return status
    }

    /// Kullanıcı Ayarlar'a gidip izni verdiğinde otomatik yakalamak için yoklamayı başlat.
    public func startPolling(interval: Duration = .seconds(2)) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                let new = self.fda.currentStatus()
                if new != self.status {
                    self.status = new
                    if new == .granted { self.onGranted?() }
                }
                if new == .granted { self.pollTask = nil; return }
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
