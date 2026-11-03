//
//  HourAngleCorrectionTests.swift
//  Adhan
//
//  Copyright © 2018 Batoul Apps. All rights reserved.
//

import XCTest
@testable import Adhan

class HourAngleCorrectionTests: XCTestCase {

    private let london = Coordinates(latitude: 51.5074, longitude: -0.1278)
    private let londonSummerDay = date(year: 2026, month: 7, day: 16)
    private let tromso = Coordinates(latitude: 69.6492, longitude: 18.9553)
    private let tromsoWinterDay = date(year: 2026, month: 1, day: 15)

    private func muslimWorldLeagueMiddleOfTheNight(_ correction: HourAngleCorrection) -> CalculationParameters {
        var params = CalculationMethod.muslimWorldLeague.params
        params.highLatitudeRule = .middleOfTheNight
        params.hourAngleCorrection = correction
        return params
    }

    private func unresolved(_ correction: HourAngleCorrection) -> CalculationParameters {
        var params = muslimWorldLeagueMiddleOfTheNight(correction)
        params.polarCircleResolution = .unresolved
        return params
    }

    private func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    func testDefaultHourAngleCorrectionIsIterative() {
        XCTAssertEqual(CalculationParameters(fajrAngle: 18, ishaAngle: 18).hourAngleCorrection, .iterative)
        for method in CalculationMethod.allCases {
            XCTAssertEqual(method.params.hourAngleCorrection, .iterative, "\(method)")
        }
    }

    func testLondonSummerIshaWithSinglePass() {
        let times = PrayerTimes(coordinates: london, date: londonSummerDay, calculationParameters: muslimWorldLeagueMiddleOfTheNight(.singlePass))!
        XCTAssertEqual(utc(times.isha), "2026-07-16 23:34")
    }

    func testLondonSummerIshaWithIterative() {
        let times = PrayerTimes(coordinates: london, date: londonSummerDay, calculationParameters: muslimWorldLeagueMiddleOfTheNight(.iterative))!
        XCTAssertEqual(utc(times.isha), "2026-07-16 23:38")
    }

    func testLondonSummerOtherTimesAgreeBetweenCorrections() {
        let singlePass = PrayerTimes(coordinates: london, date: londonSummerDay, calculationParameters: muslimWorldLeagueMiddleOfTheNight(.singlePass))!
        let iterative = PrayerTimes(coordinates: london, date: londonSummerDay, calculationParameters: muslimWorldLeagueMiddleOfTheNight(.iterative))!
        XCTAssertEqual(singlePass.fajr, iterative.fajr)
        XCTAssertEqual(singlePass.sunrise, iterative.sunrise)
        XCTAssertEqual(singlePass.dhuhr, iterative.dhuhr)
        XCTAssertEqual(singlePass.asr, iterative.asr)
        XCTAssertEqual(singlePass.maghrib, iterative.maghrib)
    }

    func testTromsoWinterDayWithSinglePassKeepsTheUnorderedTimesOf140() {
        let times = PrayerTimes(coordinates: tromso, date: tromsoWinterDay, calculationParameters: unresolved(.singlePass))!
        XCTAssertEqual(utc(times.fajr), "2026-01-15 05:14")
        XCTAssertEqual(utc(times.sunrise), "2026-01-15 10:22")
        XCTAssertEqual(utc(times.dhuhr), "2026-01-15 10:55")
        XCTAssertEqual(utc(times.asr), "2026-01-15 11:32")
        XCTAssertEqual(utc(times.maghrib), "2026-01-15 11:26")
        XCTAssertEqual(utc(times.isha), "2026-01-15 16:22")
    }

    func testTromsoWinterDayWithIterativeAndUnresolvedReturnsNil() {
        XCTAssertNil(PrayerTimes(coordinates: tromso, date: tromsoWinterDay, calculationParameters: unresolved(.iterative)))
    }
}
