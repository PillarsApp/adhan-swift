//
//  MalaysiaTimetableTests.swift
//  Adhan
//
//  Copyright © 2018 Batoul Apps. All rights reserved.
//

import XCTest
@testable import Adhan
#if canImport(CryptoKit)
import CryptoKit
#endif

class MalaysiaTimetableTests: XCTestCase {

    private let subuh = 1
    private let syuruk = 2
    private let zohor = 4
    private let asar = 5
    private let maghrib = 6
    private let isyak = 7

    private let kualaLumpur = Coordinates(latitude: 3.1390, longitude: 101.6869)
    private let kotaKinabalu = Coordinates(latitude: 5.9749, longitude: 116.0724)
    private let shahAlam = Coordinates(latitude: 3.0733, longitude: 101.5185)
    private let singapore = Coordinates(latitude: 1.3521, longitude: 103.8198)
    private let london = Coordinates(latitude: 51.5074, longitude: -0.1278)
    private let nov2 = date(year: 2026, month: 11, day: 2)

    private let nonFinitePoints = [
        Coordinates(latitude: .nan, longitude: 101.6869),
        Coordinates(latitude: 3.1390, longitude: .nan),
        Coordinates(latitude: .infinity, longitude: 101.6869),
        Coordinates(latitude: 3.1390, longitude: -.infinity),
    ]

    private let outOfRangePoints = [
        Coordinates(latitude: 3, longitude: 1e20),
        Coordinates(latitude: 1e20, longitude: 101),
        Coordinates(latitude: 3, longitude: 9.3e13),
        Coordinates(latitude: 3, longitude: -1e20),
        Coordinates(latitude: 90.00001, longitude: 101.6869),
        Coordinates(latitude: 3.1390, longitude: 180.5),
    ]

    private func official(zone: String? = nil) -> CalculationParameters {
        var params = CalculationMethod.malaysiaOfficial.params
        params.malaysiaZone = zone
        return params
    }

    private var fallbackPreset: CalculationParameters {
        var preset = CalculationParameters(fajrAngle: 18, ishaAngle: 18)
        preset.methodAdjustments = PrayerAdjustments(fajr: 1, sunrise: -1, dhuhr: 3, asr: 1, maghrib: 2, isha: 1)
        return preset
    }

    private func instant(_ date: DateComponents, _ minuteOfDay: Int) -> Date {
        let midnight = Calendar.gregorianUTC.date(from: DateComponents(year: date.year, month: date.month, day: date.day))!
        return midnight.addingTimeInterval(TimeInterval(minuteOfDay * 60 - 8 * 3600))
    }

    private func minutes(_ clock: String) -> Int {
        let parts = clock.split(separator: ":")
        return Int(parts[0])! * 60 + Int(parts[1])!
    }

    private func clock(_ time: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", components.hour!, components.minute!)
    }

    private func six(_ times: PrayerTimes) -> [Date] {
        return [times.fajr, times.sunrise, times.dhuhr, times.asr, times.maghrib, times.isha]
    }

    private func eight(_ day: MalaysiaDay) -> [Date] {
        return [day.imsak, day.subuh, day.syuruk, day.dhuha, day.zohor, day.asar, day.maghrib, day.isyak]
    }

    private func dayOfYear(_ year: Int, _ index: Int) -> DateComponents {
        let calendar = Calendar.gregorianUTC
        let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        return calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: index, to: first)!)
    }

    private func zoneYears() throws -> [MalaysiaZoneYear] {
        return try XCTUnwrap(MalaysiaTimesCodec.decode(try XCTUnwrap(MalaysiaResources.bytes("malaysia_times"))))
    }

    private func codes(_ zones: [MalaysiaZone]) -> [String] {
        return zones.map { $0.code }
    }

    func testDecoderReadsAHandWrittenLine() throws {
        let line = "ZZZ01 2026 05380548065607211300162018582009ddeca~1301gdbfdddddd"
        let zoneYear = try XCTUnwrap(MalaysiaTimesCodec.decodeLine(ArraySlice(Array(line.utf8))))
        XCTAssertEqual(zoneYear.zone, "ZZZ01")
        XCTAssertEqual(zoneYear.year, 2026)
        XCTAssertEqual(zoneYear.dayCount, 3)
        XCTAssertEqual(Array(try XCTUnwrap(zoneYear.day(0))).map(Int.init),
                       ["05:38", "05:48", "06:56", "07:21", "13:00", "16:20", "18:58", "20:09"].map(minutes))
        XCTAssertEqual(Array(try XCTUnwrap(zoneYear.day(1))).map(Int.init),
                       ["05:38", "05:48", "06:57", "07:20", "12:57", "13:01", "19:01", "20:09"].map(minutes))
        XCTAssertEqual(Array(try XCTUnwrap(zoneYear.day(2))).map(Int.init),
                       ["05:36", "05:50", "06:57", "07:20", "12:57", "13:01", "19:01", "20:09"].map(minutes))
        XCTAssertNil(zoneYear.day(3))
    }

    func testDecoderRejectsTruncatedAndUnknownCells() {
        for line in ["ZZZ01 2026 0538054806560721130016201858", "ZZZ01 2026 05380548065607211300162018582009ddd", "ZZZ01 2026 05380548065607211300162018582009dddddddz", "ZZZ01 2026 05380548065607211300162018582009ddddddd~13", "ZZZ01 2026", "ZZZ01 x 05380548065607211300162018582009"] {
            XCTAssertNil(MalaysiaTimesCodec.decodeLine(ArraySlice(Array(line.utf8))), line)
        }
    }

    func testEveryZoneYearRowReadsBackThroughPrayerTimesAndDay() throws {
        let zoneYears = try zoneYears()
        XCTAssertEqual(zoneYears.count, 117)
        for zoneYear in zoneYears {
            let label = "\(zoneYear.zone) \(zoneYear.year)"
            XCTAssertEqual(zoneYear.dayCount, 365, label)
            let zone = try XCTUnwrap(MalaysiaZones.zone(zoneYear.zone), label)
            let parameters = official(zone: zoneYear.zone)
            for index in 0..<zoneYear.dayCount {
                let date = dayOfYear(zoneYear.year, index)
                let row = try XCTUnwrap(zoneYear.day(index)).map { instant(date, Int($0)) }
                let times = try XCTUnwrap(PrayerTimes(coordinates: zone.referencePoint, date: date, calculationParameters: parameters), "\(label) \(date)")
                XCTAssertEqual(times.source, .official, "\(label) \(date)")
                XCTAssertEqual(six(times), [row[subuh], row[syuruk], row[zohor], row[asar], row[maghrib], row[isyak]], "\(label) \(date)")
                let day = try XCTUnwrap(MalaysiaTimetable.day(zone, on: date), "\(label) \(date)")
                XCTAssertEqual(eight(day), row, "\(label) \(date)")
                XCTAssertEqual(day.source, .official)
            }
        }
    }

    func testFixedRowsFromThePublishedDataAfterCorrections() throws {
        let kualaLumpur = try XCTUnwrap(MalaysiaTimetable.day(try XCTUnwrap(MalaysiaZones.zone("WLY01")), on: nov2))
        XCTAssertEqual(eight(kualaLumpur).map(clock), ["05:38", "05:48", "06:56", "07:21", "13:00", "16:20", "18:58", "20:09"])
        let labuan = try XCTUnwrap(MalaysiaTimetable.day(try XCTUnwrap(MalaysiaZones.zone("WLY02")), on: date(year: 2027, month: 5, day: 22)))
        XCTAssertEqual(clock(labuan.maghrib), "18:28")
    }

    func testKualaLumpurOnNovember2ReadsTheWLY01Row() throws {
        let times = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: nov2, calculationParameters: official()))
        XCTAssertEqual(clock(times.fajr), "05:48")
        XCTAssertEqual(clock(times.isha), "20:09")
        XCTAssertEqual(times.source, .official)
        XCTAssertTrue(times.source.isOfficial)
        XCTAssertEqual(times.malaysiaZone?.code, "WLY01")
        XCTAssertEqual(times.malaysiaZone, MalaysiaZones.zone("WLY01"))
        XCTAssertEqual(times.malaysiaZone?.state, "Wilayah Persekutuan")
        let day = try XCTUnwrap(times.malaysiaDay)
        XCTAssertEqual(clock(day.imsak), "05:38")
        XCTAssertEqual(clock(day.dhuha), "07:21")
        XCTAssertEqual(day.zone, times.malaysiaZone)
        XCTAssertEqual(day.date.year, 2026)
        XCTAssertEqual(day.date.month, 11)
        XCTAssertEqual(day.date.day, 2)
        XCTAssertEqual(day.revision, MalaysiaTimetable.revision)
        XCTAssertEqual(day.source, .official)
    }

    func testSabahIn2027HasNoRowAndFallsBackToThePreset() throws {
        let date = date(year: 2027, month: 1, day: 1)
        let times = try XCTUnwrap(PrayerTimes(coordinates: kotaKinabalu, date: date, calculationParameters: official()))
        XCTAssertEqual(times.source, .calculatedNoRow)
        XCTAssertFalse(times.source.isOfficial)
        XCTAssertEqual(times.malaysiaZone?.code, "SBH07")
        XCTAssertNil(times.malaysiaDay)
        XCTAssertEqual(fallbackPreset.method, .other)
        let calculated = try XCTUnwrap(PrayerTimes(coordinates: kotaKinabalu, date: date, calculationParameters: fallbackPreset))
        XCTAssertEqual(six(times), six(calculated))
    }

    func testOutsideMalaysiaHasNoZone() throws {
        let times = try XCTUnwrap(PrayerTimes(coordinates: singapore, date: nov2, calculationParameters: official()))
        XCTAssertEqual(times.source, .calculatedNoZone)
        XCTAssertNil(times.malaysiaZone)
        XCTAssertNil(times.malaysiaDay)
    }

    func testManualZoneWinsOverTheCoordinates() throws {
        let times = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: nov2, calculationParameters: official(zone: "WLY02")))
        let labuan = try XCTUnwrap(MalaysiaTimetable.day(try XCTUnwrap(MalaysiaZones.zone("WLY02")), on: nov2))
        XCTAssertEqual(times.source, .official)
        XCTAssertEqual(times.malaysiaZone?.code, "WLY02")
        XCTAssertEqual(times.fajr, labuan.subuh)
        XCTAssertEqual(times.isha, labuan.isyak)
        XCTAssertEqual(times.malaysiaDay?.zone.code, "WLY02")
    }

    func testManualZoneWithAnUnknownCodeHasNoZone() throws {
        let times = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: nov2, calculationParameters: official(zone: "XXX99")))
        XCTAssertEqual(times.source, .calculatedNoZone)
        XCTAssertNil(times.malaysiaZone)
        XCTAssertNil(times.malaysiaDay)
    }

    func testRetiredZoneHasNoRowAfterItsLastDayAndNamesItsSuccessors() throws {
        let times = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: date(year: 2027, month: 3, day: 1), calculationParameters: official(zone: "SGR01")))
        XCTAssertEqual(times.source, .calculatedNoRow)
        XCTAssertEqual(times.malaysiaZone?.code, "SGR01")
        let zone = try XCTUnwrap(MalaysiaZones.zone("SGR01"))
        XCTAssertEqual(codes(zone.successors), ["SGRGBK", "SGRHLG", "SGRHSL", "SGRPTG", "SGRSPG"])
        XCTAssertNil(zone.validFrom)
        XCTAssertEqual(zone.validTo, DateComponents(year: 2026, month: 12, day: 31))
        XCTAssertEqual(MalaysiaZones.zone("SGRPTG")?.validFrom, DateComponents(year: 2027, month: 1, day: 1))
        let wly01 = try XCTUnwrap(MalaysiaZones.zone("WLY01"))
        XCTAssertNil(wly01.validFrom)
        XCTAssertNil(wly01.validTo)
        XCTAssertEqual(wly01.successors, [])
    }

    func testRetiredZoneIsListedOnlyWhileInForce() {
        let after = codes(MalaysiaZones.on(date(year: 2027, month: 1, day: 1)))
        XCTAssertTrue(after.contains("SGRPTG"))
        XCTAssertFalse(after.contains("SGR01"))
        let before = codes(MalaysiaZones.on(date(year: 2026, month: 6, day: 1)))
        XCTAssertTrue(before.contains("SGR01"))
        XCTAssertFalse(before.contains("SGRPTG"))
        XCTAssertEqual(MalaysiaZones.on(DateComponents(year: 2026, month: 6)), [])
    }

    func testSWK09IsListedButNeverResolved() throws {
        XCTAssertTrue(codes(MalaysiaZones.on(nov2)).contains("SWK09"))
        let resolved = MalaysiaZones.resolve(try XCTUnwrap(MalaysiaZones.zone("SWK09")).referencePoint, on: nov2)
        XCTAssertNotNil(resolved)
        XCTAssertNotEqual(resolved?.code, "SWK09")
    }

    func testShahAlamMovesFromSGR01ToSGRPTGAtTheNewYear() throws {
        let lastDay = try XCTUnwrap(PrayerTimes(coordinates: shahAlam, date: date(year: 2026, month: 12, day: 31), calculationParameters: official()))
        XCTAssertEqual(lastDay.source, .official)
        XCTAssertEqual(lastDay.malaysiaZone?.code, "SGR01")
        let firstDay = try XCTUnwrap(PrayerTimes(coordinates: shahAlam, date: date(year: 2027, month: 1, day: 1), calculationParameters: official()))
        XCTAssertEqual(firstDay.source, .official)
        XCTAssertEqual(firstDay.malaysiaZone?.code, "SGRPTG")
    }

    func testHanafiShiftsThePublishedAsarByTheShiftAtTheZoneReference() throws {
        let zone = try XCTUnwrap(MalaysiaZones.zone("WLY02"))
        let shafi = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: nov2, calculationParameters: official(zone: zone.code)))
        var hanafiParameters = official(zone: zone.code)
        hanafiParameters.madhab = .hanafi
        let hanafi = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: nov2, calculationParameters: hanafiParameters))
        func shiftAt(_ point: Coordinates) throws -> Int {
            let solar = try XCTUnwrap(SolarTime(date: nov2, coordinates: point))
            let double = try XCTUnwrap(solar.afternoonHours(shadowLength: 2))
            let single = try XCTUnwrap(solar.afternoonHours(shadowLength: 1))
            return Int(((double - single) * 60).rounded())
        }
        let shift = try shiftAt(zone.referencePoint)
        XCTAssertNotEqual(shift, try shiftAt(kualaLumpur))
        XCTAssertGreaterThan(shift, 0)
        XCTAssertLessThan(shift, 90)
        let shafiDay = try XCTUnwrap(shafi.malaysiaDay)
        XCTAssertEqual(hanafi.asr, shafiDay.asar.addingTimeInterval(TimeInterval(shift * 60)))
        XCTAssertEqual(hanafi.malaysiaDay?.asar, shafiDay.asar)
        XCTAssertEqual([hanafi.fajr, hanafi.dhuhr, hanafi.maghrib, hanafi.isha], [shafi.fajr, shafi.dhuhr, shafi.maghrib, shafi.isha])
    }

    func testNonFiniteCoordinateWithNoManualZoneReturnsNil() {
        for point in nonFinitePoints {
            XCTAssertNil(PrayerTimes(coordinates: point, date: nov2, calculationParameters: official()), "\(point)")
        }
    }

    func testManualZoneWinsAndTheCoordinatesAreNotValidated() throws {
        let times = try XCTUnwrap(PrayerTimes(coordinates: Coordinates(latitude: .nan, longitude: .nan), date: nov2, calculationParameters: official(zone: "WLY01")))
        XCTAssertEqual(times.source, .official)
        XCTAssertEqual(times.malaysiaZone?.code, "WLY01")
    }

    func testManualZoneOnADayWithNoRowValidatesTheCoordinates() {
        XCTAssertNil(PrayerTimes(coordinates: Coordinates(latitude: .nan, longitude: .nan), date: date(year: 2027, month: 1, day: 1), calculationParameters: official(zone: "SBH07")))
    }

    func testResolveReturnsNilOutsideTheCoordinateRange() {
        for point in nonFinitePoints + outOfRangePoints {
            XCTAssertNil(MalaysiaZones.resolve(point, on: nov2), "\(point)")
        }
    }

    func testOutOfRangeCoordinateWithNoManualZoneCalculatesWithThePreset() throws {
        XCTAssertNil(PrayerTimes(coordinates: Coordinates(latitude: 1e20, longitude: 101), date: nov2, calculationParameters: official()))
        XCTAssertNil(PrayerTimes(coordinates: Coordinates(latitude: 3, longitude: 1e20), date: nov2, calculationParameters: official()))
        let farEast = Coordinates(latitude: 3, longitude: 9.3e13)
        let times = try XCTUnwrap(PrayerTimes(coordinates: farEast, date: nov2, calculationParameters: official()))
        XCTAssertEqual(times.source, .calculatedNoZone)
        XCTAssertNil(times.malaysiaZone)
        let calculated = try XCTUnwrap(PrayerTimes(coordinates: farEast, date: nov2, calculationParameters: fallbackPreset))
        XCTAssertEqual(six(times), six(calculated))
    }

    func testDateNoTimetableCanHoldHasNoZone() throws {
        let wly01 = try XCTUnwrap(MalaysiaZones.zone("WLY01"))
        for year in [214_749, Int.min] {
            let farOff = date(year: year, month: 1, day: 1)
            XCTAssertNil(MalaysiaZones.resolve(kualaLumpur, on: farOff), "\(year)")
            XCTAssertEqual(MalaysiaZones.on(farOff), [], "\(year)")
            XCTAssertFalse(wly01.inForce(on: farOff), "\(year)")
        }
        let times = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: date(year: 214_749, month: 1, day: 1), calculationParameters: official()))
        XCTAssertEqual(times.source, .calculatedNoZone)
    }

    func testResolveAtTheFarthestReferencePointsAndBothPoles() throws {
        for code in ["JHR01", "SBH03"] {
            let zone = try XCTUnwrap(MalaysiaZones.zone(code))
            XCTAssertEqual(MalaysiaZones.resolve(zone.referencePoint, on: nov2), zone)
        }
        for latitude in [90.0, -90.0] {
            XCTAssertNil(MalaysiaZones.resolve(Coordinates(latitude: latitude, longitude: 101.6869), on: nov2))
        }
    }

    func testUserAdjustmentsMoveOnlyTheirPrayer() throws {
        let plain = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: nov2, calculationParameters: official()))
        var parameters = official()
        parameters.adjustments = PrayerAdjustments(isha: 3)
        let adjusted = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: nov2, calculationParameters: parameters))
        XCTAssertEqual(adjusted.isha, plain.isha.addingTimeInterval(3 * 60))
        XCTAssertEqual(Array(six(adjusted)[0..<5]), Array(six(plain)[0..<5]))
        XCTAssertEqual(adjusted.malaysiaDay?.isyak, plain.malaysiaDay?.isyak)
    }

    func testMethodAdjustmentsDoNotMoveTheRow() throws {
        let parameters = official()
        XCTAssertEqual(parameters.methodAdjustments.dhuhr, 3)
        let times = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: nov2, calculationParameters: parameters))
        XCTAssertEqual(times.dhuhr, instant(nov2, minutes("13:00")))
        XCTAssertEqual(times.sunrise, instant(nov2, minutes("06:56")))
    }

    func testWLY01InstantsAcross2026DoNotDependOnTheHostTimeZone() throws {
        let zoneYear = try XCTUnwrap(zoneYears().first { $0.zone == "WLY01" && $0.year == 2026 })
        let zone = try XCTUnwrap(MalaysiaZones.zone("WLY01"))
        for index in 0..<zoneYear.dayCount {
            let date = dayOfYear(2026, index)
            let row = try XCTUnwrap(zoneYear.day(index)).map { instant(date, Int($0)) }
            let times = try XCTUnwrap(PrayerTimes(coordinates: kualaLumpur, date: date, calculationParameters: official(zone: "WLY01")))
            XCTAssertEqual(six(times), [row[subuh], row[syuruk], row[zohor], row[asar], row[maghrib], row[isyak]], "\(date)")
            let day = try XCTUnwrap(MalaysiaTimetable.day(zone, on: date))
            XCTAssertEqual(eight(day), row, "\(date)")
        }
    }

    func testRevisionIsTheFirstEightHexDigitsOfBothManifestHashes() throws {
        #if canImport(CryptoKit)
        func sha256(_ name: String) throws -> String {
            let bytes = try XCTUnwrap(MalaysiaResources.bytes(name))
            return SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        }
        let times = try sha256("malaysia_times")
        let zones = try sha256("malaysia_zones")
        XCTAssertEqual(MalaysiaTimetable.revision, "\(times.prefix(8))-\(zones.prefix(8))")
        let manifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Resources/MALAYSIA_MANIFEST")
        var outputs = [String: String]()
        for line in try String(contentsOf: manifest, encoding: .utf8).split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if fields.first == "output" {
                outputs[String(fields[1])] = String(fields.last!)
            }
        }
        XCTAssertEqual(outputs["malaysia_times.txt"], times)
        XCTAssertEqual(outputs["malaysia_zones.txt"], zones)
        #else
        throw XCTSkip("CryptoKit is unavailable here; run bin/check_malaysia_data.sh against the data release's MANIFEST instead")
        #endif
    }

    func testExistingMethodsKeepTheirEnumPositions() {
        XCTAssertEqual(CalculationMethod.allCases.last, .malaysiaOfficial)
        XCTAssertEqual(CalculationMethod.allCases.firstIndex(of: .other), 12)
        XCTAssertEqual(CalculationMethod.allCases.firstIndex(of: .unifiedLondonTimes), 13)
    }

    func testExistingMethodsReportACalculatedSource() throws {
        let times = try XCTUnwrap(PrayerTimes(coordinates: london, date: date(year: 2026, month: 7, day: 16), calculationParameters: CalculationMethod.muslimWorldLeague.params))
        XCTAssertEqual(times.source, .calculated)
        XCTAssertNil(times.malaysiaZone)
        XCTAssertNil(times.malaysiaDay)
    }

    func testLondonReportsAnOfficialSourceWithoutAMalaysianRow() throws {
        let times = try XCTUnwrap(PrayerTimes(coordinates: london, date: date(year: 2026, month: 7, day: 16), calculationParameters: CalculationMethod.unifiedLondonTimes.params))
        XCTAssertEqual(times.source, .official)
        XCTAssertNil(times.malaysiaZone)
        XCTAssertNil(times.malaysiaDay)
    }
}
