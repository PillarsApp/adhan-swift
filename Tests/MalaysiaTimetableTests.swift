//
//  MalaysiaTimetableTests.swift
//  Adhan
//
//  Copyright © 2018 Batoul Apps. All rights reserved.
//

import XCTest
@testable import Adhan

class MalaysiaTimetableTests: XCTestCase {

    private func minutes(_ clock: String) -> UInt16 {
        let parts = clock.split(separator: ":")
        return UInt16(parts[0])! * 60 + UInt16(parts[1])!
    }

    func testDecoderReadsAHandWrittenLine() throws {
        let line = "ZZZ01 2026 05380548065607211300162018582009ddeca~1301gdbfdddddd"
        let zoneYear = try XCTUnwrap(MalaysiaTimesCodec.decodeLine(ArraySlice(Array(line.utf8))))
        XCTAssertEqual(zoneYear.zone, "ZZZ01")
        XCTAssertEqual(zoneYear.year, 2026)
        XCTAssertEqual(zoneYear.dayCount, 3)
        XCTAssertEqual(Array(try XCTUnwrap(zoneYear.day(0))),
                       ["05:38", "05:48", "06:56", "07:21", "13:00", "16:20", "18:58", "20:09"].map(minutes))
        XCTAssertEqual(Array(try XCTUnwrap(zoneYear.day(1))),
                       ["05:38", "05:48", "06:57", "07:20", "12:57", "13:01", "19:01", "20:09"].map(minutes))
        XCTAssertEqual(Array(try XCTUnwrap(zoneYear.day(2))),
                       ["05:36", "05:50", "06:57", "07:20", "12:57", "13:01", "19:01", "20:09"].map(minutes))
        XCTAssertNil(zoneYear.day(3))
    }

    func testDecoderRejectsTruncatedAndUnknownCells() {
        for line in ["ZZZ01 2026 0538054806560721130016201858", "ZZZ01 2026 05380548065607211300162018582009ddd", "ZZZ01 2026 05380548065607211300162018582009dddddddz", "ZZZ01 2026 05380548065607211300162018582009ddddddd~13", "ZZZ01 2026", "ZZZ01 x 05380548065607211300162018582009"] {
            XCTAssertNil(MalaysiaTimesCodec.decodeLine(ArraySlice(Array(line.utf8))), line)
        }
    }
}
