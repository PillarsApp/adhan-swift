import XCTest
@testable import Adhan

func assertInvalidCoordinates(_ error: Error, _ point: Coordinates, file: StaticString = #filePath, line: UInt = #line) {
    guard case .invalidCoordinates(let reported)? = error as? OfficialLookupError else {
        return XCTFail("\(error) is not invalidCoordinates", file: file, line: line)
    }
    XCTAssertEqual(reported.latitude.isNaN, point.latitude.isNaN, file: file, line: line)
    XCTAssertEqual(reported.longitude.isNaN, point.longitude.isNaN, file: file, line: line)
    if !point.latitude.isNaN && !point.longitude.isNaN {
        XCTAssertEqual(reported, point, file: file, line: line)
    }
}

enum ProcessTimeZone {
    static func run(_ identifier: String, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) throws {
        let previous = ProcessInfo.processInfo.environment["TZ"]
        setenv("TZ", identifier, 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        defer {
            if let previous {
                setenv("TZ", previous, 1)
            } else {
                unsetenv("TZ")
            }
            tzset()
            NSTimeZone.resetSystemTimeZone()
        }
        XCTAssertEqual(TimeZone.current.identifier, identifier, "the process time zone did not change", file: file, line: line)
        try body()
    }
}

enum PublishedVectors {
    static let directory: URL = {
        let bundled = Bundle.module.resourceURL!.appendingPathComponent("Resources/published")
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/published")
    }()

    static func data(_ path: String) throws -> Data {
        return try Data(contentsOf: directory.appendingPathComponent(path))
    }

    static func timetable(_ path: String) throws -> PublishedTimetable {
        return try PublishedTimetable(data: try data(path))
    }

    static func json(_ path: String) throws -> Any {
        return try JSONSerialization.jsonObject(with: try data(path))
    }

    static func date(_ iso: String) -> DateComponents {
        let parts = iso.split(separator: "-").map { Int($0)! }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    static func instant(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    static func parameters(_ madhab: Madhab) -> CalculationParameters {
        var parameters = CalculationMethod.ummAlQura.params
        parameters.madhab = madhab
        return parameters
    }
}

final class PublishedVectorsTests: XCTestCase {
    private struct Case {
        let name: String
        let vector: String
        let coordinates: Coordinates
        let localityId: LocalityId?
        let date: DateComponents
        let result: String
        let locality: String?
        let published: [String: String]
        let asr: [String: String]
    }

    private func cases() throws -> [Case] {
        let root = try XCTUnwrap(try PublishedVectors.json("expected.json") as? [String: Any])
        return try XCTUnwrap(root["cases"] as? [[String: Any]]).map { entry in
            let coordinates = entry["coordinates"] as! [Double]
            return Case(
                name: entry["name"] as! String,
                vector: entry["vector"] as! String,
                coordinates: Coordinates(latitude: coordinates[0], longitude: coordinates[1]),
                localityId: (entry["localityId"] as? String).map { LocalityId($0) },
                date: PublishedVectors.date(entry["date"] as! String),
                result: entry["result"] as! String,
                locality: entry["locality"] as? String,
                published: entry["published"] as? [String: String] ?? [:],
                asr: entry["asr"] as? [String: String] ?? [:])
        }
    }

    private func timetables(_ cases: [Case]) throws -> [String: PublishedTimetable] {
        var timetables = [String: PublishedTimetable]()
        for vector in Set(cases.map { $0.vector }) {
            timetables[vector] = try PublishedVectors.timetable(vector)
        }
        return timetables
    }

    func testEveryExpectedCase() throws {
        try checkEveryExpectedCase()
    }

    func testEveryExpectedCaseWhenTheProcessTimeZoneIsNotUTC() throws {
        for identifier in ["Asia/Riyadh", "America/Los_Angeles", "Pacific/Chatham"] {
            try ProcessTimeZone.run(identifier) {
                try checkEveryExpectedCase()
            }
        }
    }

    private func checkEveryExpectedCase() throws {
        let cases = try cases()
        XCTAssertEqual(cases.count, 48)
        let timetables = try timetables(cases)
        for testCase in cases {
            let timetable = try XCTUnwrap(timetables[testCase.vector])
            let lookup = try timetable.lookup(testCase.coordinates, on: testCase.date, localityId: testCase.localityId)
            switch (testCase.result, lookup) {
            case ("noLocality", .noLocality):
                break
            case ("noRow", .noRow(let locality)):
                XCTAssertEqual(locality.id.rawValue, testCase.locality, testCase.name)
            case ("row", .published(let row)):
                XCTAssertEqual(row.locality.id.rawValue, testCase.locality, testCase.name)
                XCTAssertEqual(row.date, testCase.date, testCase.name)
                for column in PublishedColumn.allCases {
                    let instant = row.published(column)
                    if let expected = testCase.published[column.rawValue] {
                        XCTAssertEqual(instant, PublishedVectors.instant(expected), "\(testCase.name) \(column.rawValue)")
                    } else {
                        XCTAssertNil(instant, "\(testCase.name) \(column.rawValue)")
                    }
                }
                XCTAssertEqual(row.authority, timetable.authority, testCase.name)
                XCTAssertEqual(row.revision, timetable.revision, testCase.name)
                XCTAssertEqual(row.asrShadow, timetable.asrShadow, testCase.name)
                for madhab in Madhab.allCases {
                    let label = "\(testCase.name) \(madhab)"
                    let times = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(madhab)), label)
                    XCTAssertEqual(times.asr, PublishedVectors.instant(testCase.asr[madhab == .hanafi ? "hanafi" : "shafi"]!), label)
                    XCTAssertEqual(times.fajr, row.published(.fajr), label)
                    XCTAssertEqual(times.sunrise, row.published(.sunrise), label)
                    XCTAssertEqual(times.dhuhr, row.published(.dhuhr), label)
                    XCTAssertEqual(times.maghrib, row.published(.maghrib), label)
                    XCTAssertEqual(times.isha, row.published(.isha), label)
                }
            default:
                XCTFail("\(testCase.name): expected \(testCase.result), got \(lookup)")
            }
        }
    }

    func testEveryValidVectorValidates() throws {
        for vector in ["kacst-like", "shapes", "dst", "late-isha", "two-zones", "edge-values"] {
            let timetable = try PublishedVectors.timetable("valid/\(vector).ott")
            XCTAssertNoThrow(try timetable.validateAllRows(), vector)
        }
    }

    func testEveryMalformedVectorFailsAtItsStage() throws {
        let index = try XCTUnwrap(try PublishedVectors.json("malformed/index.json") as? [[String: Any]])
        let stages = Dictionary(uniqueKeysWithValues: index.map { ($0["file"] as! String, $0["stage"] as! String) })
        let rules = Dictionary(uniqueKeysWithValues: index.map { ($0["file"] as! String, $0["rule"] as! String) })
        let files = try FileManager.default.contentsOfDirectory(atPath: PublishedVectors.directory.appendingPathComponent("malformed").path)
            .filter { $0.hasSuffix(".ott") }
        XCTAssertEqual(Set(stages.keys), Set(files))
        var checked = 0
        func check(_ error: Error, _ file: String, _ stage: String) {
            guard let formatError = error as? PublishedTimetable.FormatError else {
                return XCTFail("\(file): \(error) is not a FormatError")
            }
            XCTAssertEqual(formatError.rule.rawValue, rules[file], file)
            XCTAssertTrue(formatError.message.hasPrefix(formatError.rule.rawValue), file)
            checked += 1
            print("malformed \(file): \(stage): \(formatError.message)")
        }
        for (file, stage) in stages.sorted(by: { $0.key < $1.key }) {
            let data = try PublishedVectors.data("malformed/\(file)")
            if stage == "decode" {
                XCTAssertThrowsError(try PublishedTimetable(data: data), file) { error in
                    check(error, file, stage)
                }
            } else {
                let timetable: PublishedTimetable
                do {
                    timetable = try PublishedTimetable(data: data)
                } catch {
                    XCTFail("\(file) failed to decode but should fail validation: \(error)")
                    continue
                }
                XCTAssertThrowsError(try timetable.validateAllRows(), file) { error in
                    check(error, file, stage)
                }
            }
        }
        XCTAssertEqual(checked, files.count)
        print("malformed files checked for stage and rule: \(checked)")
    }

    func testKacstLikeExposesItsHeader() throws {
        let timetable = try PublishedVectors.timetable("valid/kacst-like.ott")
        XCTAssertEqual(timetable.authority, "sa-umm-al-qura")
        XCTAssertEqual(timetable.revision, "12")
        XCTAssertEqual(timetable.coverage.from, DateComponents(year: 2026, month: 1, day: 1))
        XCTAssertEqual(timetable.coverage.to, DateComponents(year: 2027, month: 12, day: 31))
        XCTAssertEqual(timetable.columns, [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha])
        XCTAssertEqual(timetable.asrShadow, 1)
        XCTAssertEqual(timetable.localities.map { $0.id.rawValue }, ["1001", "1002", "1003"])
        let riyadh = try XCTUnwrap(timetable.locality(LocalityId("1001")))
        XCTAssertEqual(riyadh.name("ar"), "الرياض")
        XCTAssertEqual(riyadh.name("fr"), "Riyadh")
        XCTAssertEqual(riyadh.group, "1001")
        XCTAssertEqual(riyadh.referencePoint.latitude, 24.67)
        XCTAssertEqual(riyadh.referencePoint.longitude, 46.69)
        XCTAssertNil(timetable.locality(LocalityId("9999")))
    }

    func testShapesExposesValidityAndSuccessors() throws {
        let timetable = try PublishedVectors.timetable("valid/shapes.ott")
        let old = try XCTUnwrap(timetable.locality(LocalityId("old")))
        XCTAssertNil(old.validFrom)
        XCTAssertEqual(old.validTo, DateComponents(year: 2026, month: 12, day: 31))
        XCTAssertEqual(old.successors, [LocalityId("new")])
        XCTAssertTrue(old.inForce(on: DateComponents(year: 2026, month: 12, day: 31)))
        XCTAssertFalse(old.inForce(on: DateComponents(year: 2027, month: 1, day: 1)))
        XCTAssertEqual(old.name("en"), "old")
        let fresh = try XCTUnwrap(timetable.locality(LocalityId("new")))
        XCTAssertEqual(fresh.validFrom, DateComponents(year: 2027, month: 1, day: 1))
        XCTAssertFalse(fresh.inForce(on: DateComponents(year: 2026, month: 12, day: 31)))
        let point = Coordinates(latitude: 15, longitude: 48)
        XCTAssertEqual(try timetable.localityAt(point, on: DateComponents(year: 2026, month: 6, day: 1)), old)
        XCTAssertEqual(try timetable.localityAt(point, on: DateComponents(year: 2027, month: 6, day: 1)), fresh)
    }

    func testOutOfRangeCoordinatesAreACallerError() throws {
        let timetable = try PublishedVectors.timetable("valid/shapes.ott")
        let june = DateComponents(year: 2026, month: 6, day: 1)
        for point in [Coordinates(latitude: .nan, longitude: 48), Coordinates(latitude: 15, longitude: .infinity), Coordinates(latitude: 90.5, longitude: 48), Coordinates(latitude: 15, longitude: -180.5)] {
            XCTAssertThrowsError(try timetable.localityAt(point, on: june), "\(point)") { error in
                assertInvalidCoordinates(error, point)
            }
            XCTAssertThrowsError(try timetable.lookup(point, on: june), "\(point)") { error in
                assertInvalidCoordinates(error, point)
            }
        }
        guard case .published(let row) = try timetable.lookup(Coordinates(latitude: .nan, longitude: 48), on: DateComponents(year: 2026, month: 12, day: 30), localityId: LocalityId("old")) else {
            return XCTFail("a manual id with NaN coordinates gave no row")
        }
        XCTAssertEqual(row.locality.id, LocalityId("old"))
    }

    func testEveryRuleHasAMalformedVector() throws {
        let index = try XCTUnwrap(try PublishedVectors.json("malformed/index.json") as? [[String: Any]])
        XCTAssertEqual(Set(PublishedRule.allCases.map(\.rawValue)), Set(index.map { $0["rule"] as! String }))
    }
}
