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
    private let suva = Coordinates(latitude: -18.1416, longitude: 178.4419)
    private let suvaDayWhoseTransitWraps = date(year: 2026, month: 9, day: 20)
    private let chathamIslands = Coordinates(latitude: -43.95, longitude: -176.55)
    private let chathamDayWhoseTransitWraps = date(year: 2026, month: 2, day: 4)

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

    private func utcTimes(_ times: PrayerTimes) -> [String] {
        return [times.fajr, times.sunrise, times.dhuhr, times.asr, times.maghrib, times.isha].map(utc)
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

    func testSuvaDayWhoseTransitWrapsWithSinglePassKeepsThe140Day() {
        let times = PrayerTimes(coordinates: suva, date: suvaDayWhoseTransitWraps, calculationParameters: unresolved(.singlePass))!
        XCTAssertEqual(utcTimes(times), [
            "2026-09-20 16:45", "2026-09-20 17:57", "2026-09-21 00:00",
            "2026-09-21 03:23", "2026-09-21 06:02", "2026-09-21 07:10",
        ])
    }

    func testSuvaDayWhoseTransitWrapsWithIterativeKeepsTheDateLineCorrection() {
        let times = PrayerTimes(coordinates: suva, date: suvaDayWhoseTransitWraps, calculationParameters: unresolved(.iterative))!
        XCTAssertEqual(utcTimes(times), [
            "2026-09-19 16:46", "2026-09-19 17:58", "2026-09-20 00:01",
            "2026-09-20 03:23", "2026-09-20 06:02", "2026-09-20 07:10",
        ])
    }

    func testChathamIslandsDayWhoseTransitWrapsWithSinglePassKeepsThe140Day() {
        let times = PrayerTimes(coordinates: chathamIslands, date: chathamDayWhoseTransitWraps, calculationParameters: unresolved(.singlePass))!
        XCTAssertEqual(utcTimes(times), [
            "2026-02-03 14:52", "2026-02-03 16:49", "2026-02-04 00:01",
            "2026-02-04 03:57", "2026-02-04 07:10", "2026-02-04 08:59",
        ])
    }

    func testChathamIslandsDayWhoseTransitWrapsWithIterativeKeepsTheDateLineCorrection() {
        let times = PrayerTimes(coordinates: chathamIslands, date: chathamDayWhoseTransitWraps, calculationParameters: unresolved(.iterative))!
        XCTAssertEqual(utcTimes(times), [
            "2026-02-04 14:54", "2026-02-04 16:51", "2026-02-05 00:01",
            "2026-02-05 03:55", "2026-02-05 07:09", "2026-02-05 08:57",
        ])
    }
}
