import Foundation
import Darwin

/// CPU kullanım anlık görüntüsü (Activity Monitor kırılımına denk: Kullanıcı = user+nice).
public struct CPUUsage: Sendable, Equatable {
    public let total: Double    // busy = user + system (0...1)
    public let user: Double     // kullanıcı + nice
    public let system: Double
    public let perCore: [Double]
    public var idle: Double { max(0, 1 - total) }
    public static let zero = CPUUsage(total: 0, user: 0, system: 0, perCore: [])
}

/// CPU kullanımı. Ardışık örnekler arasındaki tick farkından hesaplar.
public final class CPUUsageSampler {
    private var previous: [UInt32]?

    public init() {}

    /// İlk çağrı taban oluşturur → .zero.
    public func sample() -> CPUUsage {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0
        let err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCpus, &cpuInfo, &numCpuInfo)
        guard err == KERN_SUCCESS, let info = cpuInfo else { return .zero }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let n = Int(numCpus)
        let states = Int(CPU_STATE_MAX)
        var ticks = [UInt32](repeating: 0, count: n * states)
        for i in 0..<(n * states) { ticks[i] = UInt32(bitPattern: info[i]) }

        var perCore = [Double](repeating: 0, count: n)
        var totalBusy = 0.0, totalAll = 0.0, totalUser = 0.0, totalSystem = 0.0
        if let prev = previous, prev.count == ticks.count {
            for c in 0..<n {
                let base = c * states
                func d(_ s: Int32) -> Double { Double(ticks[base + Int(s)] &- prev[base + Int(s)]) }
                let user = d(CPU_STATE_USER) + d(CPU_STATE_NICE)
                let sys = d(CPU_STATE_SYSTEM)
                let busy = user + sys
                let all = busy + d(CPU_STATE_IDLE)
                perCore[c] = all > 0 ? busy / all : 0
                totalBusy += busy; totalAll += all; totalUser += user; totalSystem += sys
            }
        }
        previous = ticks
        guard totalAll > 0 else { return CPUUsage(total: 0, user: 0, system: 0, perCore: perCore) }
        return CPUUsage(total: totalBusy / totalAll, user: totalUser / totalAll,
                        system: totalSystem / totalAll, perCore: perCore)
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
        // Activity Monitor "Kullanılan Bellek" = App Belleği (internal − purgeable) + Wired + Compressed.
        let appMemory = max(0, Int64(stats.internal_page_count) - Int64(stats.purgeable_count))
        let used = (appMemory + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
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
