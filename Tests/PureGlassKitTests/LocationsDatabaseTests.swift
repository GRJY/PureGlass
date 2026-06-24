import XCTest
@testable import PureGlassKit

final class LocationsDatabaseTests: XCTestCase {
    func testNotEmpty() {
        XCTAssertFalse(LocationsDatabase().locations.isEmpty)
    }

    func testUniqueIDs() {
        let ids = LocationsDatabase().locations.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Konum ID'leri benzersiz olmalı")
    }

    func testNoTildeInPaths() {
        for loc in LocationsDatabase().locations {
            XCTAssertFalse(loc.url.path.contains("~"), "Yol ~ içermemeli: \(loc.url.path)")
            XCTAssertTrue(loc.url.path.hasPrefix("/"), "Mutlak yol olmalı: \(loc.url.path)")
        }
    }

    func testUserSpaceExcludesRootLocations() {
        let db = LocationsDatabase()
        XCTAssertTrue(db.userSpaceLocations.allSatisfy { !$0.requiresRoot })
        XCTAssertTrue(db.locations.contains { $0.requiresRoot }, "En az bir root konumu tanımlı olmalı")
    }

    func testEveryUserLocationChildIsValidUnderGuard() {
        let db = LocationsDatabase()
        let guardian = SafetyGuard(database: db)
        for loc in db.locations {
            // Kökün kendisi reddedilmeli
            XCTAssertThrowsError(try guardian.validate(loc.url), "Kök silinememeli: \(loc.id)")
            // Kökün altındaki bir çocuk kabul edilmeli
            let child = loc.url.appending(path: "child-item")
            XCTAssertNoThrow(try guardian.validate(child), "Çocuk geçerli olmalı: \(loc.id)")
        }
    }

    func testCategoriesHaveTitlesAndSymbols() {
        for c in ScanCategory.allCases {
            XCTAssertFalse(c.title.isEmpty)
            XCTAssertFalse(c.symbolName.isEmpty)
        }
    }
}
