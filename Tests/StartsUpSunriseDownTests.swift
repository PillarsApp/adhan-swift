import XCTest
@testable import Adhan

class StartsUpSunriseDownTests: XCTestCase {
    private struct Vector: Decodable {
        let method: String
        let prayer: String
        let secondsPastMinute: Double
        let latitude: Double
        let longitude: Double
        let date: String
        let expected: [String: String]
    }

    private struct Vectors: Decodable {
        let cases: [Vector]
    }

    private static var methods: [String: CalculationMethod] { [
        "umm_al_qura": .ummAlQura,
        "unified_london_times": .unifiedLondonTimes,
    ] }

    private static var prayers: [String: Prayer] { [
        "fajr": .fajr,
        "sunrise": .sunrise,
        "dhuhr": .dhuhr,
        "asr": .asr,
        "maghrib": .maghrib,
        "isha": .isha,
    ] }

    private func vectors() throws -> [Vector] {
        let path = "Resources/rounding/vectors.json"
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(path)
        if let bundled = Bundle.module.resourceURL?.appendingPathComponent(path),
            FileManager.default.fileExists(atPath: bundled.path) {
            url = bundled
        }
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url)).cases
    }

    private func instant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    func testEveryRoundingGivesTheMinuteOfEachVector() throws {
        let cases = try vectors()
        XCTAssertEqual(cases.count, 20)
        for vector in cases {
            let method = try XCTUnwrap(Self.methods[vector.method])
            let prayer = try XCTUnwrap(Self.prayers[vector.prayer])
            let parts = vector.date.split(separator: "-").compactMap { Int($0) }
            let date = DateComponents(year: parts[0], month: parts[1], day: parts[2])
            let coordinates = Coordinates(latitude: vector.latitude, longitude: vector.longitude)
            XCTAssertEqual(Set(vector.expected.keys), Set(Rounding.allCases.map(\.rawValue)))
            for rounding in Rounding.allCases {
                var parameters = method.params
                parameters.rounding = rounding
                let times = try XCTUnwrap(PrayerTimes(coordinates: coordinates, date: date, calculationParameters: parameters))
                XCTAssertEqual(
                    instant(times.time(for: prayer)),
                    vector.expected[rounding.rawValue],
                    "\(vector.method) \(vector.prayer) at \(vector.secondsPastMinute) s past a minute, \(rounding.rawValue)"
                )
            }
        }
    }

    func testSunnahTimesRoundUpToTheNextMinuteWhenAnyPartOfAMinuteIsPast() throws {
        let riyadh = Coordinates(latitude: 24.7136, longitude: 46.6753)
        var parameters = CalculationMethod.ummAlQura.params
        parameters.rounding = .startsUpSunriseDown
        let calendar = Calendar.gregorianUTC
        let start = try XCTUnwrap(DateComponents(calendar: calendar, year: 2026, month: 1, day: 1).date)
        var partMinutes = 0
        var mismatches = [Int]()
        for offset in 0..<365 {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start))
            let today = try XCTUnwrap(PrayerTimes(coordinates: riyadh, date: calendar.dateComponents([.year, .month, .day], from: day), calculationParameters: parameters))
            let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
            let tomorrow = try XCTUnwrap(PrayerTimes(coordinates: riyadh, date: calendar.dateComponents([.year, .month, .day], from: nextDay), calculationParameters: parameters))

            let nightMicroseconds = Int64((tomorrow.fajr.timeIntervalSince(today.maghrib) * 1_000_000).rounded())
            let maghribMicroseconds = Int64((today.maghrib.timeIntervalSince1970 * 1_000_000).rounded())
            func upToMinute(_ microseconds: Int64) -> Int64 {
                let minute: Int64 = 60_000_000
                return (microseconds + minute - 1) / minute * minute
            }
            let middle = maghribMicroseconds + nightMicroseconds / 2
            let lastThird = maghribMicroseconds + nightMicroseconds * 2 / 3
            if middle % 60_000_000 != 0 {
                partMinutes += 1
            }

            let sunnah = try XCTUnwrap(SunnahTimes(from: today))
            let microseconds = { (date: Date) in Int64((date.timeIntervalSince1970 * 1_000_000).rounded()) }
            if microseconds(sunnah.middleOfTheNight) != upToMinute(middle) || microseconds(sunnah.lastThirdOfTheNight) != upToMinute(lastThird) {
                mismatches.append(offset)
            }
        }
        XCTAssertGreaterThan(partMinutes, 0, "some nights must split off the minute")
        XCTAssertEqual(mismatches, [])
    }

    func testEveryRoundingKeepsItsPosition() {
        XCTAssertEqual(Rounding.allCases.map(\.rawValue), ["nearest", "up", "none", "startsUpSunriseDown"])
    }

    func testTheNewRoundingSurvivesEncodingAndDecoding() throws {
        var parameters = CalculationMethod.ummAlQura.params
        parameters.rounding = .startsUpSunriseDown
        let decoded = try JSONDecoder().decode(CalculationParameters.self, from: JSONEncoder().encode(parameters))
        XCTAssertEqual(decoded.rounding, .startsUpSunriseDown)
    }
}
