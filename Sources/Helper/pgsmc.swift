// pgsmc — PureGlass'in fan kontrolü için minimal root yardımcısı.
// AppleSMC'ye fan modu (F0Md) ve hedef RPM (F0Tg) YAZAR. Root gerektirir; uygulama
// bunu yalnızca `AdminShell` (yönetici parolası) ile çalıştırır.
//
//   pgsmc auto         → F0Md = 0 (otomatik)
//   pgsmc set <rpm>    → F0Md = 1 (manuel) + F0Tg = <rpm>  (rpm SMC min/maks'a kıstırılır)

import Foundation
import IOKit

@main
struct PGSMC {
    static func main() {
        let SIZE = 80
        let kRead: UInt8 = 5, kWrite: UInt8 = 6, kInfo: UInt8 = 9

        var conn: io_connect_t = 0
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0, IOServiceOpen(svc, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            FileHandle.standardError.write("pgsmc: AppleSMC açılamadı\n".data(using: .utf8)!)
            exit(2)
        }
        IOObjectRelease(svc)

        func code(_ s: String) -> UInt32 { var r: UInt32 = 0; for c in s.utf8.prefix(4) { r = (r << 8) | UInt32(c) }; return r }
        func setU32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) { b[o] = UInt8(v & 0xff); b[o+1] = UInt8((v>>8)&0xff); b[o+2] = UInt8((v>>16)&0xff); b[o+3] = UInt8((v>>24)&0xff) }
        func getU32(_ b: [UInt8], _ o: Int) -> UInt32 { UInt32(b[o]) | UInt32(b[o+1])<<8 | UInt32(b[o+2])<<16 | UInt32(b[o+3])<<24 }
        func typeStr(_ t: UInt32) -> String { String(bytes: [UInt8(t>>24&0xff),UInt8(t>>16&0xff),UInt8(t>>8&0xff),UInt8(t&0xff)], encoding: .ascii) ?? "" }

        func call(_ inb: [UInt8]) -> [UInt8]? {
            var o = [UInt8](repeating: 0, count: SIZE); var sz = SIZE
            let kr = inb.withUnsafeBytes { ip in o.withUnsafeMutableBytes { op in
                IOConnectCallStructMethod(conn, 2, ip.baseAddress, SIZE, op.baseAddress, &sz)
            }}
            return kr == kIOReturnSuccess ? o : nil
        }
        func keyInfo(_ key: String) -> (size: UInt32, type: UInt32)? {
            var i = [UInt8](repeating: 0, count: SIZE); setU32(&i, 0, code(key)); i[42] = kInfo
            guard let o = call(i), o[40] == 0 else { return nil }
            return (getU32(o, 28), getU32(o, 32))
        }
        func readFloat(_ key: String) -> Float? {
            guard let (size, type) = keyInfo(key), size > 0 else { return nil }
            var r = [UInt8](repeating: 0, count: SIZE); setU32(&r, 0, code(key)); setU32(&r, 28, size); setU32(&r, 32, type); r[42] = kRead
            guard let o = call(r), o[40] == 0, typeStr(type) == "flt " else { return nil }
            let b = Array(o[48..<80])
            return Float(bitPattern: UInt32(b[0]) | UInt32(b[1])<<8 | UInt32(b[2])<<16 | UInt32(b[3])<<24)
        }
        func write(_ key: String, _ bytes: [UInt8]) -> Bool {
            guard let (size, type) = keyInfo(key) else { return false }
            var b = [UInt8](repeating: 0, count: SIZE)
            setU32(&b, 0, code(key)); setU32(&b, 28, size); setU32(&b, 32, type); b[42] = kWrite
            for i in 0..<min(Int(size), bytes.count) { b[48 + i] = bytes[i] }
            guard let o = call(b), o[40] == 0 else { return false }
            return true
        }
        func floatBytes(_ f: Float) -> [UInt8] { let r = f.bitPattern; return [UInt8(r&0xff), UInt8((r>>8)&0xff), UInt8((r>>16)&0xff), UInt8((r>>24)&0xff)] }

        let args = CommandLine.arguments
        guard args.count >= 2 else { print("usage: pgsmc auto | set <rpm>"); exit(1) }

        func readByte(_ key: String) -> UInt8? {
            guard let (size, type) = keyInfo(key), size > 0 else { return nil }
            var r = [UInt8](repeating: 0, count: SIZE); setU32(&r, 0, code(key)); setU32(&r, 28, size); setU32(&r, 32, type); r[42] = kRead
            guard let o = call(r), o[40] == 0 else { return nil }
            return o[48]
        }

        var ok = false
        switch args[1] {
        case "auto":
            ok = write("F0Md", [0]) && (readByte("F0Md") ?? 99) == 0   // yaz-geri-oku doğrula
        case "set":
            guard args.count >= 3, let req = Float(args[2]) else { exit(1) }
            let mn = readFloat("F0Mn") ?? 0
            let mx = readFloat("F0Mx") ?? 7200
            let rpm = Swift.max(mn, Swift.min(mx, req))
            let wMode = write("F0Md", [1])
            let wTarget = write("F0Tg", floatBytes(rpm))
            // Doğrula: manuel mod gerçekten devrede mi (F0Md == 1). F0Tg geri-okuması
            // bazı SMC sürümlerinde anlık hedefe eşit gelmeyebilir, o yüzden moda bakıyoruz.
            ok = wMode && wTarget && (readByte("F0Md") ?? 0) == 1
        default:
            print("pgsmc: bilinmeyen komut"); exit(1)
        }

        IOServiceClose(conn)
        exit(ok ? 0 : 3)
    }
}
