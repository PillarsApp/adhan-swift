import Adhan
import Foundation
import XCTest

final class WifaqulReferenceTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Provenance: Decodable { let toleranceSeconds: Double }
        let provenance: Provenance
        let cases: [ReferenceCase]
    }

    private struct ReferenceCase: Decodable {
        let name: String
        let date: String
        let latitude: Double
        let longitude: Double
        let madhab: String
        let fajrRule: String
        let ishaRule: String
        let expected: [String: String]
    }

    func testIndependentAstronomyReferences() throws {
        let resource = try XCTUnwrap(
            Bundle.module.url(
                forResource: "wifaqul-astronomy-engine", withExtension: "json", subdirectory: "Resources"
            ))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: resource))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for reference in fixture.cases {
            let components = reference.date.split(separator: "-").compactMap { Int($0) }
            var parameters = CalculationMethod.wifaqulUlama.params
            parameters.madhab = reference.madhab == "hanafi" ? .hanafi : .shafi
            parameters.wifaqulOptions = WifaqulOptions(
                fajrRule: reference.fajrRule == "nisf_al_layl" ? .nisfAlLayl : .aqrabulAyyam,
                ishaRule: reference.ishaRule == "seventh_of_night" ? .seventhOfNight : .longestDay
            )
            let times = try XCTUnwrap(
                PrayerTimes(
                    coordinates: Coordinates(latitude: reference.latitude, longitude: reference.longitude),
                    date: DateComponents(year: components[0], month: components[1], day: components[2]),
                    calculationParameters: parameters
                ), reference.name)
            let actual = [
                "fajr": times.fajr, "sunrise": times.sunrise, "dhuhr": times.dhuhr,
                "asr": times.asr, "maghrib": times.maghrib, "isha": times.isha,
            ]
            for (prayer, expected) in reference.expected {
                let expectedDate = try XCTUnwrap(formatter.date(from: expected))
                let actualDate = try XCTUnwrap(actual[prayer])
                XCTAssertEqual(
                    actualDate.timeIntervalSince1970, expectedDate.timeIntervalSince1970,
                    accuracy: fixture.provenance.toleranceSeconds,
                    "\(reference.name) \(prayer): \(actualDate) versus \(expectedDate)")
            }
        }
    }
}
