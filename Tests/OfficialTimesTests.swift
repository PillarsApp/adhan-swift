import XCTest
@testable import Adhan

final class OfficialTimesTests: XCTestCase {
    private let riyadh = Coordinates(latitude: 24.7136, longitude: 46.6753)
    private let firstDay = DateComponents(year: 2026, month: 1, day: 1)

    private func row() throws -> OfficialRow {
        let timetable = try PublishedVectors.timetable("valid/kacst-like.ott")
        guard case .published(let row) = try timetable.lookup(riyadh, on: firstDay) else {
            XCTFail("Riyadh on 2026-01-01 gave no row")
            throw XCTSkip("no row")
        }
        return row
    }

    private func six(_ times: PrayerTimes) -> [Date] {
        return [times.fajr, times.sunrise, times.dhuhr, times.asr, times.maghrib, times.isha]
    }

    func testOfficialTimesCarryTheirSourceAndRow() throws {
        let row = try row()
        let times = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.shafi)))
        XCTAssertEqual(times.source, .official)
        XCTAssertTrue(times.source.isOfficial)
        XCTAssertEqual(times.officialRow?.locality, row.locality)
        XCTAssertEqual(times.officialRow?.published(.fajr), row.published(.fajr))
        XCTAssertEqual(times.coordinates, row.locality.referencePoint)
        XCTAssertEqual(times.date, row.date)
        XCTAssertEqual(times.date, firstDay)
        XCTAssertNil(times.malaysiaZone)
        XCTAssertNil(times.malaysiaDay)
    }

    func testUserAdjustmentsMoveOnlyTheirPrayer() throws {
        let row = try row()
        let plain = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.shafi)))
        let adjusted = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.shafi), adjustments: PrayerAdjustments(fajr: 1, sunrise: -2, dhuhr: 3, asr: -4, maghrib: 5, isha: -6)))
        let shifts: [Double] = [1, -2, 3, -4, 5, -6]
        for (index, shift) in shifts.enumerated() {
            XCTAssertEqual(six(adjusted)[index], six(plain)[index].addingTimeInterval(shift * 60), "prayer \(index)")
        }
    }

    func testTheAsrAdjustmentIsAddedAfterTheHanafiShift() throws {
        let row = try row()
        let hanafi = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.hanafi)))
        let adjusted = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.hanafi), adjustments: PrayerAdjustments(asr: 7)))
        XCTAssertEqual(hanafi.asr, PublishedVectors.instant("2026-01-01T12:40:00Z"))
        XCTAssertEqual(adjusted.asr, hanafi.asr.addingTimeInterval(7 * 60))
    }

    func testAdjustmentsDefaultToTheParameters() throws {
        let row = try row()
        let shifts = PrayerAdjustments(fajr: 2, isha: -3)
        var parameters = PublishedVectors.parameters(.shafi)
        parameters.adjustments = shifts
        let fromParameters = try XCTUnwrap(PrayerTimes(official: row, parameters: parameters))
        let explicit = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.shafi), adjustments: shifts))
        XCTAssertEqual(six(fromParameters), six(explicit))
        XCTAssertEqual(fromParameters.fajr, row.published(.fajr)?.addingTimeInterval(2 * 60))
    }

    func testMethodAdjustmentsAndRoundingMoveNothing() throws {
        let row = try row()
        let plain = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.shafi)))
        var parameters = PublishedVectors.parameters(.shafi)
        parameters.methodAdjustments = PrayerAdjustments(fajr: 10, sunrise: 10, dhuhr: 10, asr: 10, maghrib: 10, isha: 10)
        parameters.rounding = .up
        XCTAssertEqual(six(try XCTUnwrap(PrayerTimes(official: row, parameters: parameters))), six(plain))
    }

    func testSunnahTimesCalculateTomorrowAtTheReferencePoint() throws {
        let row = try row()
        let times = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.shafi)))
        let sunnah = try XCTUnwrap(SunnahTimes(from: times))
        let tomorrow = try XCTUnwrap(PrayerTimes(coordinates: row.locality.referencePoint, date: DateComponents(year: 2026, month: 1, day: 2), calculationParameters: PublishedVectors.parameters(.shafi)))
        let midpoint = times.maghrib.addingTimeInterval(tomorrow.fajr.timeIntervalSince(times.maghrib) / 2)
        XCTAssertLessThanOrEqual(abs(sunnah.middleOfTheNight.timeIntervalSince(midpoint)), 30)
        XCTAssertGreaterThan(sunnah.lastThirdOfTheNight, sunnah.middleOfTheNight)
        XCTAssertLessThan(sunnah.lastThirdOfTheNight, tomorrow.fajr)
    }

    func testPrayerNavigationReadsThePublishedInstants() throws {
        let row = try row()
        let times = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.shafi)))
        let nine = PublishedVectors.instant("2026-01-01T09:00:00Z")
        XCTAssertEqual(times.currentPrayer(at: nine), .dhuhr)
        XCTAssertEqual(times.nextPrayer(at: nine), .asr)
        XCTAssertEqual(times.time(for: .maghrib), PublishedVectors.instant("2026-01-01T14:16:00Z"))
    }
}
