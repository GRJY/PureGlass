import Foundation
import IOKit

/// Bir fanın anlık durumu.
public struct FanInfo: Sendable, Equatable {
    public let current: Double
    public let min: Double
    public let max: Double
    public let target: Double
    public let auto: Bool
}

/// AppleSMC'den (System Management Controller) SALT-OKUNUR veri okur: sıcaklık, fan.
///
/// Önemli: Swift struct dolgusu C `SMCKeyData_t` (80 byte) ile uyuşmadığı için
/// IOConnectCallStructMethod'a HAM 80-byte tampon veriyoruz; alanlar bilinen ofsetlere
/// elle yazılır (key@0, keyInfo.dataSize@28, dataType@32, result@40, data8@42, bytes@48).
/// Bu yaklaşım gerçek M1 donanımında doğrulandı.
public final class SMCReader {
    private var connection: io_connect_t = 0
    private let opened: Bool

    private static let size = 80
    private static let cmdRead: UInt8 = 5
    private static let cmdInfo: UInt8 = 9

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { opened = false; return nil }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard result == kIOReturnSuccess else { opened = false; return nil }
        opened = true
    }

    deinit { if opened { IOServiceClose(connection) } }

    // MARK: - Public okuma

    public func fan(index: Int = 0) -> FanInfo? {
        let p = "F\(index)"
        guard let cur = readDouble("\(p)Ac") else { return nil }
        return FanInfo(
            current: cur,
            min: readDouble("\(p)Mn") ?? 0,
            max: readDouble("\(p)Mx") ?? 0,
            target: readDouble("\(p)Tg") ?? 0,
            auto: (readDouble("\(p)Md") ?? 0) < 0.5
        )
    }

    public func fanCount() -> Int { Int(readDouble("FNum") ?? 0) }

    /// CPU bölgesi sıcaklığı (M1'de Tc0a/Tc0b ortalaması).
    public func cpuTemperature() -> Double? {
        average(["Tc0a", "Tc0b", "Tc0c", "Tc0d"])
    }

    public func batteryTemperature() -> Double? { plausible(readDouble("TB0T")) }

    /// Sistemdeki en sıcak anlamlı sensör.
    public func peakTemperature() -> Double? {
        ["Tc0a", "Tc0b", "Ts0P", "Ts1P", "TW0P", "TH0x", "TB0T", "Tg0D"]
            .compactMap { plausible(readDouble($0)) }
            .max()
    }

    // MARK: - Düşük seviye

    public func readDouble(_ key: String) -> Double? {
        guard opened else { return nil }
        var inb = [UInt8](repeating: 0, count: Self.size)
        setU32(&inb, 0, fourChar(key)); inb[42] = Self.cmdInfo
        guard let info = call(inb), info[40] == 0 else { return nil }
        let dataSize = getU32(info, 28), dataType = getU32(info, 32)
        guard dataSize > 0 else { return nil }

        var rb = [UInt8](repeating: 0, count: Self.size)
        setU32(&rb, 0, fourChar(key)); setU32(&rb, 28, dataSize); setU32(&rb, 32, dataType); rb[42] = Self.cmdRead
        guard let out = call(rb), out[40] == 0 else { return nil }
        let b = Array(out[48..<80])

        switch typeString(dataType) {
        case "flt ":
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "fpe2":
            return Double((UInt16(b[0]) << 8 | UInt16(b[1])) >> 2)
        case "sp78":
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256.0
        case "ui8 ", "ui8":
            return Double(b[0])
        case "ui16":
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32":
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        default:
            return nil
        }
    }

    // MARK: - Yardımcılar

    private func average(_ keys: [String]) -> Double? {
        let vals = keys.compactMap { plausible(readDouble($0)) }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private func plausible(_ v: Double?) -> Double? {
        guard let v, v > 1, v < 130 else { return nil }
        return v
    }

    private func call(_ inb: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: Self.size)
        var osz = Self.size
        let kr = inb.withUnsafeBytes { ip in
            output.withUnsafeMutableBytes { op in
                IOConnectCallStructMethod(connection, 2, ip.baseAddress, Self.size, op.baseAddress, &osz)
            }
        }
        return kr == kIOReturnSuccess ? output : nil
    }

    private func fourChar(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for c in s.utf8.prefix(4) { r = (r << 8) | UInt32(c) }
        return r
    }
    private func typeString(_ t: UInt32) -> String {
        String(bytes: [UInt8(t >> 24 & 0xff), UInt8(t >> 16 & 0xff), UInt8(t >> 8 & 0xff), UInt8(t & 0xff)], encoding: .ascii) ?? ""
    }
    private func setU32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        b[o] = UInt8(v & 0xff); b[o + 1] = UInt8((v >> 8) & 0xff); b[o + 2] = UInt8((v >> 16) & 0xff); b[o + 3] = UInt8((v >> 24) & 0xff)
    }
    private func getU32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}
