import XCTest
@testable import PureGlassKit

final class SystemMetricsTests: XCTestCase {
    func testMemoryStatsPlausible() {
        let m = SystemMetrics.memory()
        XCTAssertGreaterThan(m.total, 0)
        XCTAssertGreaterThan(m.used, 0)
        XCTAssertLessThan(m.used, m.total)
        XCTAssertTrue((0...1).contains(m.usedFraction))
    }

    func testCPUSamplerInRange() {
        let s = CPUUsageSampler()
        _ = s.sample()                      // taban
        // küçük bir iş yap
        var x = 0.0; for i in 0..<200_000 { x += Double(i).squareRoot() }
        _ = x
        let (total, perCore) = s.sample()
        XCTAssertTrue((0...1).contains(total))
        XCTAssertFalse(perCore.isEmpty)
        XCTAssertTrue(perCore.allSatisfy { (0...1).contains($0) })
    }

    func testMemoryPressureValid() {
        XCTAssertTrue([1, 2, 4].contains(SystemMetrics.pressure()))
    }
}

final class SMCReaderTests: XCTestCase {
    func testFanReadable() throws {
        guard let smc = SMCReader() else { throw XCTSkip("AppleSMC açılamadı (ör. VM)") }
        guard let fan = smc.fan() else { throw XCTSkip("Fan bu cihazda yok (ör. MacBook Air)") }
        XCTAssertGreaterThan(fan.max, 0, "Maks RPM > 0 olmalı")
        XCTAssertGreaterThanOrEqual(fan.current, 0)
        XCTAssertLessThanOrEqual(fan.current, fan.max + 1)
    }

    func testTemperatureReadable() throws {
        guard let smc = SMCReader() else { throw XCTSkip("AppleSMC yok") }
        let temp = smc.peakTemperature()
        if let t = temp {
            XCTAssertTrue((1...130).contains(t), "Sıcaklık makul aralıkta olmalı: \(t)")
        } else {
            throw XCTSkip("Bu cihazda okunabilir SMC sıcaklık anahtarı bulunamadı")
        }
    }
}
