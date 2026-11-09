import XCTest
@testable import Adhan

final class MalaysiaSourceTests: XCTestCase {
    private let kualaLumpur = Coordinates(latitude: 3.1390, longitude: 101.6869)
    private let kotaKinabalu = Coordinates(latitude: 5.9749, longitude: 116.0724)
    private let singapore = Coordinates(latitude: 1.3521, longitude: 103.8198)
    private let nov2 = DateComponents(year: 2026, month: 11, day: 2)
    private let source = MalaysiaTimetable.source

    private func official(zone: String? = nil) -> CalculationParameters {
        var parameters = CalculationMethod.malaysiaOfficial.params
        parameters.malaysiaZone = zone
        return parameters
    }

    private func row(_ lookup: OfficialLookup, file: StaticString = #filePath, line: UInt = #line) throws -> OfficialRow {
        guard case .published(let row) = lookup else {
            XCTFail("expected a row, got \(lookup)", file: file, line: line)
            throw XCTSkip("no row")
        }
        return row
    }

    func testTheSourceNamesItsAuthorityAndRevision() {
        XCTAssertEqual(source.authority, "jakim")
        XCTAssertEqual(source.revision, MalaysiaTimetable.revision)
    }

    func testKualaLumpurOnNovember2IsTheWLY01Row() throws {
        let row = try row(try source.lookup(kualaLumpur, on: nov2))
        XCTAssertEqual(row.locality.id, LocalityId("WLY01"))
        XCTAssertEqual(row.date, nov2)
        XCTAssertEqual(row.authority, "jakim")
        XCTAssertEqual(row.revision, MalaysiaTimetable.revision)
        XCTAssertEqual(row.asrShadow, 1)
        XCTAssertEqual(row.utcOffset, 8 * 3600)
        XCTAssertEqual(row.columns, [.imsak, .fajr, .sunrise, .dhuha, .dhuhr, .asr, .maghrib, .isha])
        XCTAssertNil(row.published(.asrHanafi))
        XCTAssertNil(row.published(.eid))
        let day = try XCTUnwrap(MalaysiaTimetable.day(try XCTUnwrap(MalaysiaZones.zone("WLY01")), on: nov2))
        XCTAssertEqual(row.published(.imsak), day.imsak)
        XCTAssertEqual(row.published(.fajr), day.subuh)
        XCTAssertEqual(row.published(.sunrise), day.syuruk)
        XCTAssertEqual(row.published(.dhuha), day.dhuha)
        XCTAssertEqual(row.published(.dhuhr), day.zohor)
        XCTAssertEqual(row.published(.asr), day.asar)
        XCTAssertEqual(row.published(.maghrib), day.maghrib)
        XCTAssertEqual(row.published(.isha), day.isyak)
        XCTAssertEqual(row.published(.fajr), PublishedVectors.instant("2026-11-01T21:48:00Z"))
    }

    func testAManualUnknownCodeIsNoLocality() throws {
        guard case .noLocality = try source.lookup(kualaLumpur, on: nov2, localityId: LocalityId("XXX00")) else {
            return XCTFail("an unknown code resolved")
        }
        XCTAssertNil(source.locality(LocalityId("XXX00")))
    }

    func testOutsideMalaysiaIsNoLocality() throws {
        guard case .noLocality = try source.lookup(singapore, on: nov2) else {
            return XCTFail("Singapore resolved")
        }
        XCTAssertNil(try source.localityAt(singapore, on: nov2))
    }

    func testANonDayOrAnOutOfRangeCoordinateIsACallerError() {
        let nonDay = DateComponents(year: 2026, month: 2, day: 30)
        XCTAssertThrowsError(try source.lookup(kualaLumpur, on: nonDay)) { error in
            XCTAssertEqual(error as? OfficialLookupError, .invalidDate(nonDay))
        }
        XCTAssertThrowsError(try source.lookup(kualaLumpur, on: nonDay, localityId: LocalityId("WLY01"))) { error in
            XCTAssertEqual(error as? OfficialLookupError, .invalidDate(nonDay))
        }
        let farEast = Coordinates(latitude: 3, longitude: 9.3e13)
        XCTAssertThrowsError(try source.localityAt(farEast, on: nov2)) { error in
            XCTAssertEqual(error as? OfficialLookupError, .invalidCoordinates(farEast))
        }
        let nan = Coordinates(latitude: .nan, longitude: 101.6869)
        XCTAssertThrowsError(try source.lookup(nan, on: nov2)) { error in
            assertInvalidCoordinates(error, nan)
        }
        XCTAssertNoThrow(try source.lookup(nan, on: nov2, localityId: LocalityId("WLY01")))
    }

    func testKotaKinabaluIn2027HasNoRow() throws {
        guard case .noRow(let locality) = try source.lookup(kotaKinabalu, on: DateComponents(year: 2027, month: 1, day: 1)) else {
            return XCTFail("Kota Kinabalu in 2027 gave something other than noRow")
        }
        XCTAssertEqual(locality.id, LocalityId("SBH07"))
    }

    func testARetiredZoneIsALocalityWithValidityAndSuccessors() throws {
        let selangor = try XCTUnwrap(source.locality(LocalityId("SGR01")))
        let zone = try XCTUnwrap(MalaysiaZones.zone("SGR01"))
        XCTAssertEqual(selangor.group, "Selangor")
        XCTAssertNil(selangor.validFrom)
        XCTAssertEqual(selangor.validTo, DateComponents(year: 2026, month: 12, day: 31))
        XCTAssertEqual(selangor.successors.map { $0.rawValue }, ["SGRGBK", "SGRHLG", "SGRHSL", "SGRPTG", "SGRSPG"])
        XCTAssertEqual(selangor.name("ms"), zone.areas)
        XCTAssertEqual(selangor.name("en"), "SGR01")
        XCTAssertEqual(selangor.referencePoint, zone.referencePoint)
        XCTAssertTrue(selangor.inForce(on: nov2))
        XCTAssertFalse(selangor.inForce(on: DateComponents(year: 2027, month: 1, day: 1)))
        XCTAssertEqual(try source.localityAt(kualaLumpur, on: nov2), source.locality(LocalityId("WLY01")))
    }

    func testLocalitiesIsTheWholeCatalogInCatalogOrder() {
        let localities = source.localities
        XCTAssertEqual(localities.count, 69)
        XCTAssertEqual(localities.map { $0.id.rawValue }, MalaysiaZones.all.map { $0.code })
        XCTAssertTrue(localities.contains { $0.id.rawValue == "SWK09" })
    }

    func testAManualRetiredZoneIsUsedAndHasNoRowAfterItsLastDay() throws {
        let march = DateComponents(year: 2027, month: 3, day: 1)
        guard case .noRow(let locality) = try source.lookup(kualaLumpur, on: march, localityId: LocalityId("SGR01")) else {
            return XCTFail("SGR01 in 2027 gave something other than noRow")
        }
        XCTAssertEqual(locality.id, LocalityId("SGR01"))
        let automatic = try row(try source.lookup(kualaLumpur, on: march))
        XCTAssertNotEqual(automatic.locality.id, LocalityId("SGR01"))
    }

    func testTheLegacyMethodExposesTheRowOnAnOfficialDay() throws {
        let times = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: nov2, calculationParameters: official()))
        XCTAssertEqual(times.source, .official)
        let row = try XCTUnwrap(times.officialRow)
        XCTAssertEqual(row.locality.id, LocalityId("WLY01"))
        XCTAssertEqual(times.malaysiaZone, MalaysiaZones.zone("WLY01"))
        XCTAssertEqual(times.malaysiaDay?.subuh, row.published(.fajr))
        XCTAssertEqual(times.fajr, row.published(.fajr))
        let generic = try XCTUnwrap(PrayerTimes(official: row, parameters: official()))
        XCTAssertEqual(generic.asr, times.asr)
        XCTAssertEqual(generic.isha, times.isha)
        var hanafi = official()
        hanafi.madhab = .hanafi
        let legacyHanafi = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: nov2, calculationParameters: hanafi))
        XCTAssertEqual(try XCTUnwrap(PrayerTimes(official: row, parameters: hanafi)).asr, legacyHanafi.asr)
        XCTAssertGreaterThan(legacyHanafi.asr, times.asr)
    }

    func testAnOfficialRowFromTheMalaysianSourceReportsItsDayAndZone() throws {
        let row = try row(try source.lookup(kualaLumpur, on: nov2, localityId: LocalityId("WLY01")))
        let times = try XCTUnwrap(PrayerTimes(official: row, parameters: official()))
        XCTAssertEqual(times.source, .official)
        XCTAssertEqual(times.malaysiaDay?.zone.code, "WLY01")
        XCTAssertEqual(times.malaysiaDay?.subuh, row.published(.fajr))
        XCTAssertEqual(times.malaysiaZone?.code, "WLY01")
        XCTAssertEqual(times.officialRow?.locality.id, LocalityId("WLY01"))
        let riyadh = try self.row(try PublishedVectors.timetable("valid/kacst-like.ott").lookup(Coordinates(latitude: 24.7136, longitude: 46.6753), on: DateComponents(year: 2026, month: 1, day: 1)))
        let saudi = try XCTUnwrap(PrayerTimes(official: riyadh, parameters: PublishedVectors.parameters(.shafi)))
        XCTAssertEqual(saudi.source, .official)
        XCTAssertNil(saudi.malaysiaDay)
        XCTAssertNil(saudi.malaysiaZone)
        XCTAssertEqual(saudi.officialRow?.locality.id, LocalityId("1001"))
        let lookalike = try PublishedTimetable(data: Data("""
            OTT 1
            {"authority":"jakim","revision":1,"part":"all","coverage":["2026-11-02","2026-11-02"],"columns":["imsak","fajr","sunrise","dhuha","dhuhr","asr","maghrib","isha"],"asrShadow":1,"zones":[{"id":"Asia/Kuala_Lumpur","offsets":[["2026-11-02",480]]}],"localities":[{"id":"WLY01","group":"g","zone":0,"names":{},"ref":[3139000,101687000],"point":{"radiusM":1000}}]}
            WLY01 2026-11-02 05300540065907001300161018501900

            """.utf8))
        let published = try XCTUnwrap(PrayerTimes(official: try self.row(try lookalike.lookup(kualaLumpur, on: nov2, localityId: LocalityId("WLY01"))), parameters: official()))
        XCTAssertNil(published.malaysiaDay, "a published file shaped like the embedded data is not the embedded data")
        XCTAssertNil(published.malaysiaZone)
        XCTAssertEqual(published.officialRow?.revision, "1")
    }

    func testTheLegacyMethodKeepsTheZoneOnADayTheSourceRejects() throws {
        let julianLeapDay = DateComponents(year: 1500, month: 2, day: 29)
        XCTAssertThrowsError(try source.lookup(kualaLumpur, on: julianLeapDay)) { error in
            XCTAssertEqual(error as? OfficialLookupError, .invalidDate(julianLeapDay))
        }
        for parameters in [official(), official(zone: "WLY01")] {
            let times = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: julianLeapDay, calculationParameters: parameters), "\(String(describing: parameters.malaysiaZone))")
            XCTAssertEqual(times.source, .calculatedNoRow, "\(String(describing: parameters.malaysiaZone))")
            XCTAssertEqual(times.malaysiaZone?.code, "WLY01", "\(String(describing: parameters.malaysiaZone))")
            XCTAssertNil(times.officialRow)
        }
        let singapore = try XCTUnwrap(PrayerTimes(coordinates: singapore, date: julianLeapDay, calculationParameters: official()))
        XCTAssertEqual(singapore.source, .calculatedNoZone)
    }

    func testTheLegacyMethodHasNoRowOnAFallbackDay() throws {
        let noRow = try XCTUnwrap(PrayerTimes(coordinates: kotaKinabalu, date: DateComponents(year: 2027, month: 1, day: 1), calculationParameters: official()))
        XCTAssertEqual(noRow.source, .calculatedNoRow)
        XCTAssertNil(noRow.officialRow)
        XCTAssertEqual(noRow.malaysiaZone, MalaysiaZones.zone("SBH07"))
        let noZone = try XCTUnwrap(PrayerTimes(coordinates: singapore, date: nov2, calculationParameters: official()))
        XCTAssertEqual(noZone.source, .calculatedNoZone)
        XCTAssertNil(noZone.officialRow)
        XCTAssertNil(noZone.malaysiaZone)
    }
}
