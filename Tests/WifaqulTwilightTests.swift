import Foundation
import XCTest

@testable import Adhan

final class WifaqulTwilightTests: XCTestCase {
    private let calendar = Calendar.gregorianUTC
    private let london = Coordinates(latitude: 51.5074, longitude: -0.1278)

    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private func solar(_ date: Date, _ coordinates: Coordinates) throws -> SolarTime {
        try XCTUnwrap(
            SolarTime(date: calendar.dateComponents([.year, .month, .day], from: date), coordinates: coordinates))
    }

    private func raw(_ solar: SolarTime, _ angle: Double, evening: Bool) -> Date? {
        solar.timeForTwilightAngle(Angle(-angle), afterTransit: evening).flatMap { calendar.date(from: $0) }
    }

    func testNearTangentDawnReferencesUseActualLastValidDay() throws {
        let cases: [(Coordinates, Int, TimeInterval)] = [
            (Coordinates(latitude: 61.2181, longitude: -149.9003), 17, 10 * 3600 + 27 * 60 + 50),
            (Coordinates(latitude: 62.0355, longitude: 129.6755), 16, -86400 + 15 * 3600 + 33 * 60 + 14),
        ]
        for (coordinates, referenceDay, expectedOffset) in cases {
            let referenceDate = try day(2026, 4, referenceDay)
            let referenceSolar = try solar(referenceDate, coordinates)
            let dawn = try XCTUnwrap(raw(referenceSolar, 18, evening: false))
            XCTAssertEqual(dawn.timeIntervalSince(referenceDate), expectedOffset, accuracy: 1)
            let nextSolar = try solar(referenceDate.addingTimeInterval(86400), coordinates)
            XCTAssertNil(raw(nextSolar, 18, evening: false))
            let summer = try day(2026, 6, 21)
            let result = try times(summer, coordinates)
            XCTAssertEqual(result.fajr.timeIntervalSince(summer), dawn.timeIntervalSince(referenceDate))
            let hours = dawn.timeIntervalSince(referenceDate) / 3600
            XCTAssertEqual(referenceSolar.twilightAltitude(hours: hours), -18, accuracy: 0.001)
        }
    }

    func testTwilightSolverRejectsNonfiniteTargetsAndMeetsGeometricAngles() throws {
        let referenceDate = try day(2026, 4, 17)
        let reference = try solar(referenceDate, Coordinates(latitude: 61.2181, longitude: -149.9003))
        for evening in [false, true] {
            for target in [Double.nan, .infinity, -.infinity] {
                XCTAssertNil(reference.timeForTwilightAngle(Angle(target), afterTransit: evening))
            }
            for angle in [15.0, 18.0] {
                if let event = raw(reference, angle, evening: evening) {
                    let hours = event.timeIntervalSince(referenceDate) / 3600
                    XCTAssertEqual(reference.twilightAltitude(hours: hours), -angle, accuracy: 0.0043)
                }
            }
        }
    }

    func testLegacyMethodsRetainOriginalAstronomicalTwilight() throws {
        let date = try day(2026, 2, 12)
        let coordinates = Coordinates(latitude: 30.0444, longitude: 31.2357)
        let reference = try solar(date, coordinates)
        for method in [CalculationMethod.karachi, .muslimWorldLeague, .egyptian, .northAmerica] {
            var params = method.params
            params.rounding = .none
            let result = try times(date, coordinates, params)
            let dawn = try XCTUnwrap(reference.timeForSolarAngle(Angle(-params.fajrAngle), afterTransit: false))
            let isha = try XCTUnwrap(reference.timeForSolarAngle(Angle(-params.ishaAngle), afterTransit: true))
            XCTAssertEqual(result.fajr, calendar.date(from: dawn))
            XCTAssertEqual(result.isha, calendar.date(from: isha))
            params.wifaqulOptions = WifaqulOptions(fajrRule: .nisfAlLayl, ishaRule: .seventhOfNight)
            let withIrrelevantOptions = try times(date, coordinates, params)
            XCTAssertEqual(withIrrelevantOptions.fajr, result.fajr)
            XCTAssertEqual(withIrrelevantOptions.isha, result.isha)
        }
    }

    private func parameters(_ options: WifaqulOptions? = nil) -> CalculationParameters {
        var parameters = CalculationMethod.wifaqulUlama.params
        parameters.rounding = .none
        parameters.wifaqulOptions = options
        return parameters
    }

    private func times(_ date: Date, _ coordinates: Coordinates, _ parameters: CalculationParameters? = nil) throws
        -> PrayerTimes
    {
        try XCTUnwrap(
            PrayerTimes(
                coordinates: coordinates,
                date: calendar.dateComponents([.year, .month, .day], from: date),
                calculationParameters: parameters ?? self.parameters()))
    }

    private func capOffset(_ year: Int, _ coordinates: Coordinates) throws -> TimeInterval {
        var longest = -Double.infinity
        var offset: TimeInterval?
        for number in 15...25 {
            let date = try day(year, 6, number)
            let reference = try solar(date, coordinates)
            _ = try XCTUnwrap(calendar.date(from: reference.sunrise))
            let sunset = try XCTUnwrap(calendar.date(from: reference.sunset))
            if reference.daylightDuration > longest {
                longest = reference.daylightDuration
                offset = sunset.timeIntervalSince(date) + 65 * 60
            }
        }
        return try XCTUnwrap(offset)
    }

    func testOrdinaryAstronomyLatitudeBoundaryAndBothMadhabs() throws {
        let date = try day(2026, 2, 12)
        let locations = [
            london, Coordinates(latitude: 57.1497, longitude: -2.0943),
            Coordinates(latitude: 30.0444, longitude: 31.2357), Coordinates(latitude: -33.9249, longitude: 18.4241),
            Coordinates(latitude: 47.9999, longitude: 0), Coordinates(latitude: 48, longitude: 0),
            Coordinates(latitude: 48.0001, longitude: 0),
        ]
        for coordinates in locations {
            let reference = try solar(date, coordinates)
            var previousAsr: Date?
            for madhab in [Madhab.shafi, .hanafi] {
                var params = parameters()
                params.madhab = madhab
                let result = try times(date, coordinates, params)
                XCTAssertEqual(result.fajr, raw(reference, 18, evening: false))
                XCTAssertEqual(result.isha, raw(reference, coordinates.latitude >= 48 ? 15 : 18, evening: true))
                XCTAssertEqual(result.sunrise, calendar.date(from: reference.sunrise))
                XCTAssertEqual(result.dhuhr, calendar.date(from: reference.transit)?.addingTimeInterval(240))
                XCTAssertEqual(result.maghrib, calendar.date(from: reference.sunset)?.addingTimeInterval(300))
                let asr = try XCTUnwrap(reference.afternoon(shadowLength: madhab.shadowLength))
                XCTAssertEqual(result.asr, calendar.date(from: asr))
                if let previousAsr = previousAsr { XCTAssertGreaterThan(result.asr, previousAsr) }
                previousAsr = result.asr
            }
        }
    }

    func testFullSeasonsPreserveValidDawnAndRebaseLastValidDayAcrossLeapYears() throws {
        for year in [2024, 2026] {
            for coordinates in [london, Coordinates(latitude: 57.1497, longitude: -2.0943)] {
                let start = try day(year, 1, 1)
                var lastValidOffset: TimeInterval?
                var missingDays = 0
                var transitions = 0
                var wasMissing = false
                let cap = try capOffset(year, coordinates)
                var lateExistingIsha = 0
                var missingIsha = 0
                for index in 0..<(year == 2024 ? 366 : 365) {
                    let date = start.addingTimeInterval(Double(index) * 86400)
                    let reference = try solar(date, coordinates)
                    let result = try times(date, coordinates)
                    let dawn = raw(reference, 18, evening: false)
                    if let dawn = dawn {
                        XCTAssertEqual(result.fajr, dawn)
                        lastValidOffset = dawn.timeIntervalSince(date)
                    } else {
                        missingDays += 1
                        XCTAssertEqual(result.fajr.timeIntervalSince(date), try XCTUnwrap(lastValidOffset))
                    }
                    if (dawn == nil) != wasMissing { transitions += 1 }
                    wasMissing = dawn == nil
                    let isha = raw(reference, 15, evening: true)
                    let limit = date.addingTimeInterval(cap)
                    XCTAssertEqual(result.isha, isha.map { min($0, limit) } ?? limit)
                    if let isha = isha, isha > limit { lateExistingIsha += 1 }
                    if isha == nil { missingIsha += 1 }
                }
                XCTAssertEqual(transitions, 2)
                XCTAssertGreaterThan(missingDays, 30)
                XCTAssertGreaterThan(lateExistingIsha, 0)
                if coordinates.latitude == london.latitude {
                    XCTAssertEqual(missingIsha, 0)
                } else {
                    XCTAssertGreaterThan(missingIsha, 0)
                }
            }
        }
    }

    func testAlternativeRulesUsePreviousNightAndOnlyCapPresentIshaBySeventh() throws {
        let options = WifaqulOptions(fajrRule: .nisfAlLayl, ishaRule: .seventhOfNight)
        let aberdeen = Coordinates(latitude: 57.1497, longitude: -2.0943)
        var sawPresent = false
        var sawAbsent = false
        var distinguishedNights = false
        var distinguishedDailySunset = false
        let cap = try capOffset(2026, aberdeen)
        for index in 0..<100 {
            let date = try day(2026, 5, 1).addingTimeInterval(Double(index) * 86400)
            let reference = try solar(date, aberdeen)
            let sunrise = try XCTUnwrap(calendar.date(from: reference.sunrise))
            let sunset = try XCTUnwrap(calendar.date(from: reference.sunset))
            let previous = try solar(date.addingTimeInterval(-86400), aberdeen)
            let tomorrow = try solar(date.addingTimeInterval(86400), aberdeen)
            let previousSunset = try XCTUnwrap(calendar.date(from: previous.sunset))
            let tomorrowSunrise = try XCTUnwrap(calendar.date(from: tomorrow.sunrise))
            let result = try times(date, aberdeen, parameters(options))
            if let dawn = raw(reference, 18, evening: false) {
                XCTAssertEqual(result.fajr, dawn)
            } else {
                let midpoint = previousSunset.addingTimeInterval(sunrise.timeIntervalSince(previousSunset) / 2)
                XCTAssertEqual(result.fajr, midpoint.roundedMinute(rounding: .none))
                let wrongMidpoint = sunset.addingTimeInterval(tomorrowSunrise.timeIntervalSince(sunset) / 2 - 86400)
                if midpoint != wrongMidpoint { distinguishedNights = true }
            }
            if let isha = raw(reference, 15, evening: true) {
                sawPresent = true
                let seventh = sunset.addingTimeInterval(tomorrowSunrise.timeIntervalSince(sunset) / 7)
                XCTAssertEqual(result.isha, min(isha, seventh).roundedMinute(rounding: .none))
            } else {
                sawAbsent = true
                XCTAssertEqual(result.isha, date.addingTimeInterval(cap))
                if result.isha != sunset.addingTimeInterval(3900) { distinguishedDailySunset = true }
            }
        }
        XCTAssertTrue(sawPresent && sawAbsent && distinguishedNights && distinguishedDailySunset)
    }

    func testGenericHighLatitudeRulesNeverClampValidTwilightOrChangeFallbacks() throws {
        var witnessedGenericClamp = false
        for month in [4, 5, 6, 8] {
            let date = try day(2026, month, 15)
            let expected = try times(date, london)
            for rule in [HighLatitudeRule.middleOfTheNight, .seventhOfTheNight, .twilightAngle] {
                var params = parameters()
                params.highLatitudeRule = rule
                let result = try times(date, london, params)
                XCTAssertEqual(result.fajr, expected.fajr)
                XCTAssertEqual(result.isha, expected.isha)
                var generic = params
                generic.method = .other
                let ordinary = try times(date, london, generic)
                if raw(try solar(date, london), 18, evening: false) != nil && ordinary.fajr != result.fajr {
                    witnessedGenericClamp = true
                }
            }
        }
        XCTAssertTrue(witnessedGenericClamp)
    }

    func testAdjustmentsAndRoundingApplyExactlyOnce() throws {
        for month in [2, 6] {
            let date = try day(2026, month, 12)
            let baseline = try times(date, london)
            for rounding in Rounding.allCases {
                var params = parameters()
                params.rounding = rounding
                params.adjustments = PrayerAdjustments(fajr: 3, sunrise: -2, dhuhr: -7, asr: 4, maghrib: 8, isha: -6)
                let adjusted = try times(date, london, params)
                let rows: [(Date, Date, TimeInterval)] = [
                    (baseline.fajr, adjusted.fajr, 180),
                    (baseline.sunrise, adjusted.sunrise, -120), (baseline.dhuhr, adjusted.dhuhr, -420),
                    (baseline.asr, adjusted.asr, 240), (baseline.maghrib, adjusted.maghrib, 480),
                    (baseline.isha, adjusted.isha, -360),
                ]
                for (raw, actual, adjustment) in rows {
                    XCTAssertEqual(actual, raw.addingTimeInterval(adjustment).roundedMinute(rounding: rounding))
                }
            }
        }
    }

    func testCustomAnglesAreRejectedWithoutMutatingReusedParameters() throws {
        let date = try day(2026, 3, 2)
        let original = parameters()
        for index in 0..<4 {
            var invalid = original
            switch index {
            case 0: invalid.fajrAngle = 17
            case 1: invalid.ishaAngle = 15
            case 2: invalid.ishaInterval = 90
            default: invalid.maghribAngle = 4
            }
            XCTAssertNil(
                PrayerTimes(
                    coordinates: london, date: calendar.dateComponents([.year, .month, .day], from: date),
                    calculationParameters: invalid))
        }
        for latitude in [30.0, 57.0, -33.0, 48.0, 30.0] {
            let result = try times(date, Coordinates(latitude: latitude, longitude: 0), original)
            XCTAssertEqual(result.calculationParameters, original)
        }
    }

    func testLegacyCodableAndSelectedOptionsRoundTrip() throws {
        for method in CalculationMethod.allCases {
            var params = method.params
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])
            object.removeValue(forKey: "wifaqulOptions")
            let legacy = try JSONDecoder().decode(
                CalculationParameters.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(legacy, params)
            params.wifaqulOptions = WifaqulOptions(fajrRule: .nisfAlLayl, ishaRule: .seventhOfNight)
            XCTAssertEqual(
                try JSONDecoder().decode(CalculationParameters.self, from: JSONEncoder().encode(params)), params)
        }
        let existing = [
            "muslimWorldLeague", "egyptian", "karachi", "ummAlQura", "dubai", "moonsightingCommittee",
            "northAmerica", "kuwait", "qatar", "singapore", "tehran", "turkey", "other", "unifiedLondonTimes",
        ]
        XCTAssertEqual(Array(CalculationMethod.allCases.dropLast()).map(\.rawValue), existing)
    }

    func testUnsupportedPolarSolsticeAndSouthernTwilightFail() throws {
        for (latitude, month) in [(70.0, 6), (70.0, 12), (66.0, 2), (-60.0, 12), (-80.0, 6)] {
            for options in [WifaqulOptions(), WifaqulOptions(fajrRule: .nisfAlLayl)] {
                XCTAssertNil(
                    PrayerTimes(
                        coordinates: Coordinates(latitude: latitude, longitude: 0),
                        date: DateComponents(year: 2026, month: month, day: 21),
                        calculationParameters: parameters(options)))
            }
        }
    }

    func testCacheIsolationEvictionAndLongitudeMidnightRollover() throws {
        let requested = try day(2026, 6, 12)
        let expected = try times(requested, london)
        for index in 0..<40 {
            let year = 2024 + index % 3
            let coordinates = Coordinates(latitude: 51 + Double(index) / 100, longitude: -179 + Double(index) * 9)
            let date = try day(year, 6, 12)
            let result = try times(date, coordinates)
            XCTAssertEqual(result.isha, date.addingTimeInterval(try capOffset(year, coordinates)))
            let repeated = try times(date, coordinates)
            XCTAssertEqual(result.fajr, repeated.fajr)
            XCTAssertEqual(result.isha, repeated.isha)
        }
        let afterEviction = try times(requested, london)
        XCTAssertEqual(afterEviction.fajr, expected.fajr)
        XCTAssertEqual(afterEviction.isha, expected.isha)
        for longitude in [-179.0, 179.0] {
            let coordinates = Coordinates(latitude: 30, longitude: longitude)
            let result = try times(requested, coordinates)
            let reference = try solar(requested, coordinates)
            XCTAssertEqual(result.fajr, raw(reference, 18, evening: false))
            XCTAssertEqual(result.isha, raw(reference, 18, evening: true))
            if longitude < 0 {
                XCTAssertGreaterThan(result.isha, requested.addingTimeInterval(86400))
            } else {
                XCTAssertLessThan(result.fajr, requested)
            }
        }
    }

    func testUTCComponentsIgnoreTravelTimezoneAndFormattingPreservesInstant() throws {
        for (month, number) in [(3, 28), (3, 29), (10, 24), (10, 25)] {
            let date = try day(2026, month, number)
            let expected = try times(date, london)
            for identifier in ["UTC", "Europe/London", "America/New_York", "Asia/Tokyo"] {
                let zone = try XCTUnwrap(TimeZone(identifier: identifier))
                var components = DateComponents(year: 2026, month: month, day: number)
                components.timeZone = zone
                components.hour = 17
                let result = try XCTUnwrap(
                    PrayerTimes(coordinates: london, date: components, calculationParameters: parameters()))
                XCTAssertEqual(result.fajr, expected.fajr)
                XCTAssertEqual(result.isha, expected.isha)
                let formatter = ISO8601DateFormatter()
                formatter.timeZone = zone
                XCTAssertEqual(formatter.date(from: formatter.string(from: result.isha)), result.isha)
            }
        }
    }

    func testConcurrentCacheRequestsRemainDeterministic() throws {
        final class Results: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [Int: [Date]] = [:]
            func put(_ index: Int, _ dates: [Date]) {
                lock.lock()
                defer { lock.unlock() }
                values[index] = dates
            }
            func get(_ index: Int) -> [Date]? {
                lock.lock()
                defer { lock.unlock() }
                return values[index]
            }
        }
        let results = Results()
        let expected = try (0..<64).map { index -> [Date] in
            let result = try times(
                day(2024 + index % 3, 6, 1 + index % 25),
                Coordinates(latitude: 51 + Double(index % 5), longitude: Double(index % 7)))
            return [result.fajr, result.isha]
        }
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            var params = CalculationMethod.wifaqulUlama.params
            params.rounding = .none
            let result = PrayerTimes(
                coordinates: Coordinates(latitude: 51 + Double(index % 5), longitude: Double(index % 7)),
                date: DateComponents(year: 2024 + index % 3, month: 6, day: 1 + index % 25),
                calculationParameters: params)
            results.put(index, result.map { [$0.fajr, $0.isha] } ?? [])
        }
        for index in 0..<64 { XCTAssertEqual(results.get(index), expected[index]) }
    }
}
