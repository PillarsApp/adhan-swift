//
//  PublishedPerfTests.swift
//  Adhan
//
//  Copyright © 2018 Batoul Apps. All rights reserved.
//

import XCTest
@testable import Adhan

class PublishedPerfTests: XCTestCase {

    private static let localityCount = 173
    private static let repeatedLookups = 10_000

    private static let artifact: Data = {
        var text = "OTT 1\n"
        var localities = [String]()
        for index in 0..<localityCount {
            let latitude = 16_500_000 + (index * 97_003) % 15_500_000
            let longitude = 34_500_000 + (index * 131_071) % 21_000_000
            localities.append("{\"id\":\"\(1000 + index)\",\"group\":\"\(1000 + index / 13)\",\"zone\":0,\"names\":{\"en\":\"Locality \(index)\"},\"ref\":[\(latitude),\(longitude)],\"point\":{\"radiusM\":25000}}")
        }
        text += "{\"authority\":\"xx-perf\",\"revision\":1,\"part\":\"all\",\"coverage\":[\"2026-01-01\",\"2027-12-31\"],\"columns\":[\"fajr\",\"sunrise\",\"dhuhr\",\"asr\",\"maghrib\",\"isha\"],\"asrShadow\":1,\"zones\":[{\"id\":\"Asia/Riyadh\",\"offsets\":[[\"2026-01-01\",180]]}],\"localities\":[\(localities.joined(separator: ","))]}\n"
        let firstDay = [315, 397, 717, 897, 1037, 1127]
        let deltas = Array("abcdefg")
        for index in 0..<localityCount {
            for year in [2026, 2027] {
                var cells = firstDay.map { String(format: "%02d%02d", $0 / 60, $0 % 60) }.joined()
                var isha = firstDay[5]
                for day in 1..<365 {
                    var delta = ((day * 5 + index) % 7) - 3
                    if isha + delta > 1400 || isha + delta < 1100 {
                        delta = 0
                    }
                    isha += delta
                    cells += String(repeating: deltas[delta + 3], count: 6)
                }
                text += "\(1000 + index) \(year)-01-01 \(cells)\n"
            }
        }
        return text.data(using: .utf8)!
    }()

    private func milliseconds(_ work: () throws -> Void) rethrows -> Double {
        let started = DispatchTime.now().uptimeNanoseconds
        try work()
        return Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    private func median(_ samples: [Double]) -> Double {
        return samples.sorted()[samples.count / 2]
    }

    func testSyntheticArtifactDecodesAndValidates() throws {
        let timetable = try PublishedTimetable(data: Self.artifact)
        XCTAssertEqual(timetable.localities.count, Self.localityCount)
        try timetable.validateAllRows()
        guard case .published(let row) = try timetable.lookup(timetable.localities[0].referencePoint, on: DateComponents(year: 2027, month: 2, day: 8)) else {
            return XCTFail("expected a row")
        }
        XCTAssertEqual(row.locality.id.rawValue, "1000")
    }

    func testTimingsOnA173LocalityArtifact() throws {
        let data = Self.artifact
        let point = (try PublishedTimetable(data: data)).localities[Self.localityCount / 2].referencePoint
        let date = DateComponents(year: 2027, month: 2, day: 8)
        var initSamples = [Double]()
        var firstSamples = [Double]()
        var repeatedSamples = [Double]()
        var validateSamples = [Double]()
        for _ in 0..<5 {
            var timetable: PublishedTimetable! = nil
            initSamples.append(try milliseconds { timetable = try PublishedTimetable(data: data) })
            firstSamples.append(try milliseconds {
                guard case .published = try timetable.lookup(point, on: date) else {
                    return XCTFail("expected a row")
                }
            })
            repeatedSamples.append(try milliseconds {
                for i in 0..<Self.repeatedLookups {
                    let day = DateComponents(year: 2026 + i % 2, month: 1 + i % 12, day: 1 + i % 28)
                    guard case .published = try timetable.lookup(point, on: day) else {
                        return XCTFail("expected a row")
                    }
                }
            })
            validateSamples.append(try milliseconds { try PublishedTimetable(data: data).validateAllRows() })
        }
        let report = """
        published perf: \(data.count) bytes, \(Self.localityCount) localities, medians of 5
        init_ms=\(String(format: "%.3f", median(initSamples)))
        first_lookup_ms=\(String(format: "%.3f", median(firstSamples)))
        repeated_lookup_us=\(String(format: "%.3f", median(repeatedSamples) * 1_000 / Double(Self.repeatedLookups)))
        validate_all_rows_ms=\(String(format: "%.3f", median(validateSamples)))
        init samples ms: \(initSamples.map { String(format: "%.3f", $0) }.joined(separator: " "))
        """
        print(report)
    }
}
