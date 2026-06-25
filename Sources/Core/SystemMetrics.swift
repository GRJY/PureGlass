import Foundation
import Darwin

/// CPU kullanımı (toplam + çekirdek başına). Ardışık örnekler arasındaki tick farkından hesaplar.
public final class CPUUsageSampler {
    private var previous: [UInt32]?

    public init() {}

    /// (toplam 0...1, çekirdek başına [0...1]). İlk çağrı taban oluşturur → (0, []).
    public func sample() -> (total: Double, perCore: [Double]) {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0
        let err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCpus, &cpuInfo, &numCpuInfo)
        guard err == KERN_SUCCESS, let info = cpuInfo else { return (0, []) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let n = Int(numCpus)
        let states = Int(CPU_STATE_MAX)
        var ticks = [UInt32](repeating: 0, count: n * states)
        for i in 0..<(n * states) { ticks[i] = UInt32(bitPattern: info[i]) }

        var perCore = [Double](repeating: 0, count: n)
        var totalBusy = 0.0, totalAll = 0.0
        if let prev = previous, prev.count == ticks.count {
            for c in 0..<n {
                let base = c * states
                func d(_ s: Int32) -> Double { Double(ticks[base + Int(s)] &- prev[base + Int(s)]) }
                let busy = d(CPU_STATE_USER) + d(CPU_STATE_SYSTEM) + d(CPU_STATE_NICE)
                let all = busy + d(CPU_STATE_IDLE)
                perCore[c] = all > 0 ? busy / all : 0
                totalBusy += busy; totalAll += all
            }
        }
        previous = ticks
        return (totalAll > 0 ? totalBusy / totalAll : 0, perCore)
    }
}

/// Bellek kullanımı anlık görüntüsü.
public struct MemoryStats: Sendable {
    public let used: Int64
    public let total: Int64
    public let pressureLevel: Int   // 1 normal, 2 uyarı, 4 kritik
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    public var pressureTitle: String {
        switch pressureLevel { case 4: return "Kritik"; case 2: return "Uyarı"; default: return "Normal" }
    }
}

public enum SystemMetrics {
    public static func memory() -> MemoryStats {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return MemoryStats(used: 0, total: total, pressureLevel: pressure()) }
        let page = Int64(sysconf(Int32(_SC_PAGESIZE)))
        let used = (Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        return MemoryStats(used: used, total: total, pressureLevel: pressure())
    }

    public static func cpuBrand() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    /// Fan kontrolü yalnızca M1/M2'de güvenilir (Apple M3+'da "korumalı mod" ile blokluyor).
    public static var fanControlSupported: Bool {
        let b = cpuBrand()
        return b.contains("M1") || b.contains("M2")
    }

    public static func pressure() -> Int {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return Int(level)
    }
}
