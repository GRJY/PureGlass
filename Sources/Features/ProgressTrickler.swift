import Foundation
import Observation

/// L("Sızdıran", "Leaking") ilerleme: gerçek ilerleme uzun bir adımda takılsa bile gösterilen
/// yüzde yavaşça yukarı süzülür (91 → 92 → 93…), bir tavana asimptotik yaklaşır.
/// Gerçek ilerleme öne geçerse onu takip eder; iş bitince %100'e atlar.
@MainActor
@Observable
final class ProgressTrickler {
    private(set) var value: Double = 0

    private var task: Task<Void, Never>?
    private let ceiling = 0.97   // beklerken en fazla buraya kadar süzül

    func start() {
        task?.cancel()
        value = 0
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(180))
                guard let self else { return }
                if self.value < self.ceiling {
                    // kalanın küçük bir oranı kadar artır → yaklaştıkça yavaşlar
                    self.value += (self.ceiling - self.value) * 0.05
                }
            }
        }
    }

    /// Gerçek ilerleme olayı geldiğinde: yüzde gerçeğin gerisindeyse öne çek.
    func report(_ real: Double) {
        value = max(value, min(real, 0.99))
    }

    func finish() {
        task?.cancel()
        task = nil
        value = 1.0
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
