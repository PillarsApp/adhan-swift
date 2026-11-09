import XCTest
@testable import Adhan

final class HanafiParityTests: XCTestCase {
    private static let directory: URL = {
        let bundled = Bundle.module.resourceURL!.appendingPathComponent("Resources/hanafi")
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/hanafi")
    }()

    private struct Field {
        let name: String
        let madhab: Madhab
        let correction: HourAngleCorrection?

        var parameters: CalculationParameters {
            var parameters = CalculationMethod.ummAlQura.params
            parameters.madhab = madhab
            if let correction {
                parameters.hourAngleCorrection = correction
            }
            return parameters
        }
    }

    private let fields = [
        Field(name: "iterative.shafi", madhab: .shafi, correction: .iterative),
        Field(name: "iterative.hanafi", madhab: .hanafi, correction: .iterative),
        Field(name: "singlePass.shafi", madhab: .shafi, correction: .singlePass),
        Field(name: "singlePass.hanafi", madhab: .hanafi, correction: .singlePass),
        Field(name: "default.hanafi", madhab: .hanafi, correction: nil),
    ]

    func testAsrMatchesTheDartLibraryOnEveryDayOf2026AtTwelveLocalities() throws {
        let timetable = try PublishedTimetable(data: try Data(contentsOf: Self.directory.appendingPathComponent("probe.ott")))
        try timetable.validateAllRows()
        let oracle = try String(contentsOf: Self.directory.appendingPathComponent("dart-c55b113.tsv"), encoding: .utf8)
        let rows = oracle.split(separator: "\n")
        XCTAssertEqual(rows.count, 4380)
        var mismatches = [String]()
        for row in rows {
            let cells = row.split(separator: "\t").map(String.init)
            guard cells.count == 2 + fields.count else {
                XCTFail("an oracle row does not have \(2 + fields.count) cells: \(row)")
                continue
            }
            let date = PublishedVectors.date(cells[1])
            guard case .published(let official) = try timetable.lookup(Coordinates(latitude: 0, longitude: 0), on: date, localityId: LocalityId(cells[0])) else {
                XCTFail("\(cells[0]) on \(cells[1]) gave no row")
                continue
            }
            for (field, cell) in zip(fields, cells[2...]) {
                let parts = cell.split(separator: "=", maxSplits: 1).map(String.init)
                XCTAssertEqual(parts[0], field.name, cell)
                let swift = PrayerTimes(official: official, parameters: field.parameters).map { String(Int64($0.asr.timeIntervalSince1970)) } ?? "undefined"
                if swift != parts[1] {
                    mismatches.append("\(cells[0]) \(cells[1]) \(field.name) dart=\(parts[1]) swift=\(swift)")
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "\(mismatches.count) mismatches against adhan-dart c55b113:\n" + mismatches.joined(separator: "\n"))
    }

    func testTheHanafiShiftFollowsTheCallersHourAngleCorrectionAtChatham() throws {
        let file = """
            OTT 1
            {"authority":"xx-chatham","revision":1,"part":"all","coverage":["2026-02-18","2026-02-18"],"columns":["fajr","sunrise","dhuhr","asr","maghrib","isha"],"asrShadow":1,"zones":[{"id":"Pacific/Chatham","offsets":[["2026-02-18",825]]}],"localities":[{"id":"chatham","group":"chatham","zone":0,"names":{"en":"Chatham Islands"},"ref":[-43953500,-176559700],"point":{"radiusM":30000}}]}
            chatham 2026-02-18 050006301320170020302200

            """
        let timetable = try PublishedTimetable(data: Data(file.utf8))
        guard case .published(let row) = try timetable.lookup(Coordinates(latitude: -43.9535, longitude: -176.5597), on: DateComponents(year: 2026, month: 2, day: 18)) else {
            return XCTFail("Chatham gave no row")
        }
        for (correction, asr) in [(HourAngleCorrection.iterative, "2026-02-18T04:16:00Z"), (.singlePass, "2026-02-18T04:15:00Z")] {
            var parameters = CalculationMethod.ummAlQura.params
            parameters.madhab = .hanafi
            parameters.hourAngleCorrection = correction
            XCTAssertEqual(try XCTUnwrap(PrayerTimes(official: row, parameters: parameters)).asr, PublishedVectors.instant(asr), "\(correction)")
        }
    }
}
