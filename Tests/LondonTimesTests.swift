//
//  LondonTimesTests.swift
//  Adhan
//
//  Created by Omar Khan on 6/24/25.
//  Copyright © 2025 Batoul Apps. All rights reserved.
//


//
//  LondonTimesTests.swift
//  AdhanTests
//
//  Copyright © 2018 Batoul Apps. All rights reserved.
//

import XCTest
@testable import Adhan

class LondonTimesTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clear any cached data before each test
        LondonTimesLookup.clearCache()
    }
    
    func testLondonTimesDataModel() {
        let testData: [String: Any] = [
            "date": "2025-01-01",
            "fajr": "06:26",
            "sunrise": "08:03",
            "dhuhr": "12:09",
            "asr": "13:45",
            "maghrib": "16:04",
            "isha": "17:41"
        ]
        
        let londonTimes = LondonPrayerTimes(from: testData)
        XCTAssertNotNil(londonTimes)
        XCTAssertEqual(londonTimes?.date, "2025-01-01")
        XCTAssertEqual(londonTimes?.fajr, "06:26")
        XCTAssertEqual(londonTimes?.maghrib, "16:04")
    }
    
    func testLondonTimesDataModelWithMagribSpelling() {
        let testData: [String: Any] = [
            "date": "2025-01-01",
            "fajr": "06:26",
            "sunrise": "08:03",
            "dhuhr": "12:09",
            "asr": "13:45",
            "magrib": "16:04",  // Using 'magrib' spelling
            "isha": "17:41"
        ]
        
        let londonTimes = LondonPrayerTimes(from: testData)
        XCTAssertNotNil(londonTimes)
        XCTAssertEqual(londonTimes?.maghrib, "16:04")
    }
    
    func testLondonTimesParseTime() {
        let testData: [String: Any] = [
            "date": "2025-01-01",
            "fajr": "06:26",
            "sunrise": "08:03",
            "dhuhr": "12:09",
            "asr": "13:45",
            "maghrib": "16:04",
            "isha": "17:41"
        ]
        
        guard let londonTimes = LondonPrayerTimes(from: testData) else {
            XCTFail("Failed to create LondonPrayerTimes")
            return
        }
        
        let dateComponents = DateComponents(year: 2025, month: 1, day: 1)
        let parsedTime = londonTimes.parseTime("06:26", for: dateComponents)
        
        XCTAssertNotNil(parsedTime)
        let calendar = Calendar.gregorianUTC
        let components = calendar.dateComponents([.hour, .minute], from: parsedTime!)
        XCTAssertEqual(components.hour, 6)
        XCTAssertEqual(components.minute, 26)
    }
    
    func testLondonTimesLookupInitialization() {
        let jsonString = """
        {
            "city": "london",
            "times": {
                "2025-01-01": {
                    "date": "2025-01-01",
                    "fajr": "06:26",
                    "sunrise": "08:03",
                    "dhuhr": "12:09",
                    "asr": "13:45",
                    "maghrib": "16:04",
                    "isha": "17:41"
                }
            }
        }
        """
        
        XCTAssertNoThrow(try LondonTimesLookup.initialize(with: jsonString))
        
        let dateComponents = DateComponents(year: 2025, month: 1, day: 1)
        let times = LondonTimesLookup.getTimes(for: dateComponents)
        
        XCTAssertNotNil(times)
        XCTAssertEqual(times?.fajr, "06:26")
        XCTAssertEqual(times?.isha, "17:41")
    }
    
    func testLondonTimesLookupMissingDate() {
        let jsonString = """
        {
            "city": "london",
            "times": {
                "2025-01-01": {
                    "date": "2025-01-01",
                    "fajr": "06:26",
                    "sunrise": "08:03",
                    "dhuhr": "12:09",
                    "asr": "13:45",
                    "maghrib": "16:04",
                    "isha": "17:41"
                }
            }
        }
        """
        
        XCTAssertNoThrow(try LondonTimesLookup.initialize(with: jsonString))
        
        let dateComponents = DateComponents(year: 2025, month: 1, day: 2) // Different date
        let times = LondonTimesLookup.getTimes(for: dateComponents)
        
        XCTAssertNil(times)
    }
    
    func testPrayerTimesWithLondonLookup() {
        let jsonString = """
        {
            "city": "london",
            "times": {
                "2025-01-01": {
                    "date": "2025-01-01",
                    "fajr": "06:26",
                    "sunrise": "08:03",
                    "dhuhr": "12:09",
                    "asr": "13:45",
                    "maghrib": "16:04",
                    "isha": "17:41"
                }
            }
        }
        """
        
        XCTAssertNoThrow(try LondonTimesLookup.initialize(with: jsonString))
        
        let coordinates = Coordinates(latitude: 51.5074, longitude: -0.1278) // London coordinates
        let date = DateComponents(year: 2025, month: 1, day: 1)
        let params = CalculationMethod.unifiedLondonTimes.params
        
        let prayerTimes = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: params)
        
        XCTAssertNotNil(prayerTimes)
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        // Verify that the times match our lookup data (accounting for UTC conversion)
        let fajrTime = normalizeTimeString(formatter.string(from: prayerTimes!.fajr))
        let sunriseTime = normalizeTimeString(formatter.string(from: prayerTimes!.sunrise))
        let dhuhrTime = normalizeTimeString(formatter.string(from: prayerTimes!.dhuhr))
        let asrTime = normalizeTimeString(formatter.string(from: prayerTimes!.asr))
        let maghribTime = normalizeTimeString(formatter.string(from: prayerTimes!.maghrib))
        let ishaTime = normalizeTimeString(formatter.string(from: prayerTimes!.isha))
        
        XCTAssertEqual(fajrTime, "6:26 AM")
        XCTAssertEqual(sunriseTime, "8:03 AM")
        XCTAssertEqual(dhuhrTime, "12:09 PM")
        XCTAssertEqual(asrTime, "1:45 PM")
        XCTAssertEqual(maghribTime, "4:04 PM")
        XCTAssertEqual(ishaTime, "5:41 PM")
    }
    
    func testPrayerTimesWithLondonLookupAndAdjustments() {
        let jsonString = """
        {
            "city": "london",
            "times": {
                "2025-01-01": {
                    "date": "2025-01-01",
                    "fajr": "06:26",
                    "sunrise": "08:03",
                    "dhuhr": "12:09",
                    "asr": "13:45",
                    "maghrib": "16:04",
                    "isha": "17:41"
                }
            }
        }
        """
        
        XCTAssertNoThrow(try LondonTimesLookup.initialize(with: jsonString))
        
        let coordinates = Coordinates(latitude: 51.5074, longitude: -0.1278)
        let date = DateComponents(year: 2025, month: 1, day: 1)
        var params = CalculationMethod.unifiedLondonTimes.params
        params.adjustments.fajr = 5 // Add 5 minutes to Fajr
        
        let prayerTimes = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: params)
        
        XCTAssertNotNil(prayerTimes)
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        let fajrTime = normalizeTimeString(formatter.string(from: prayerTimes!.fajr))
        XCTAssertEqual(fajrTime, "6:31 AM") // 6:26 + 5 minutes = 6:31
    }
    
    func testPrayerTimesWithLondonLookupWorksWithEmbeddedData() {
        // Test that London times work without explicit initialization (using embedded data)
        LondonTimesLookup.clearCache()
        
        let coordinates = Coordinates(latitude: 51.5074, longitude: -0.1278)
        let date = DateComponents(year: 2025, month: 1, day: 1)
        let params = CalculationMethod.unifiedLondonTimes.params
        
        let prayerTimes = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: params)
        
        // Should work with embedded data
        XCTAssertNotNil(prayerTimes)
        
        // Verify the times are correct from embedded data
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        
        let fajrTime = normalizeTimeString(formatter.string(from: prayerTimes!.fajr))
        XCTAssertEqual(fajrTime, "6:26 AM")
    }
    
    func testLondonTimezoneHandling() {
        // Test that times are correctly converted from London local time to UTC
        // January 1st is in GMT (UTC+0)
        let winterDate = DateComponents(year: 2025, month: 1, day: 1)
        let winterTimes = LondonPrayerTimes(
            date: "2025-01-01",
            fajr: "06:26",
            sunrise: "08:03",
            dhuhr: "12:09",
            asr: "13:45",
            maghrib: "16:04",
            isha: "17:41"
        )
        
        // Parse winter time (GMT)
        let winterFajr = winterTimes.parseTime("06:26", for: winterDate)
        XCTAssertNotNil(winterFajr)
        
        // In January, London is GMT (UTC+0), so 06:26 London = 06:26 UTC
        let utcFormatter = DateFormatter()
        utcFormatter.dateFormat = "HH:mm"
        utcFormatter.timeZone = TimeZone(identifier: "UTC")
        XCTAssertEqual(utcFormatter.string(from: winterFajr!), "06:26")
        
        // Test summer date (BST - British Summer Time, UTC+1)
        // Note: BST typically runs from last Sunday in March to last Sunday in October
        let summerDate = DateComponents(year: 2025, month: 7, day: 1)
        let summerTimes = LondonPrayerTimes(
            date: "2025-07-01",
            fajr: "02:47",
            sunrise: "04:47",
            dhuhr: "13:10",
            asr: "17:17",
            maghrib: "21:21",
            isha: "23:21"
        )
        
        // Parse summer time (BST)
        let summerFajr = summerTimes.parseTime("02:47", for: summerDate)
        XCTAssertNotNil(summerFajr)
        
        // In July, London is BST (UTC+1), so 02:47 London = 01:47 UTC
        XCTAssertEqual(utcFormatter.string(from: summerFajr!), "01:47")
    }
    
    func testInvalidJSONHandling() {
        let invalidJSON = "{ invalid json }"
        
        XCTAssertThrowsError(try LondonTimesLookup.initialize(with: invalidJSON)) { error in
            if case let AdhanError.invalidData(message) = error {
                XCTAssertTrue(message.contains("Failed to parse JSON"))
            } else {
                XCTFail("Expected AdhanError.invalidData but got \(error)")
            }
        }
    }
}