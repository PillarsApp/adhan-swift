//
//  LondonTimesLookup.swift
//  Adhan
//
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

/**
 Data model for London prayer times from JSON lookup table.
 */
public struct LondonPrayerTimes {
    public let date: String
    public let fajr: String
    public let sunrise: String
    public let dhuhr: String
    public let asr: String
    public let maghrib: String
    public let isha: String
    
    public init(date: String, fajr: String, sunrise: String, dhuhr: String, asr: String, maghrib: String, isha: String) {
        self.date = date
        self.fajr = fajr
        self.sunrise = sunrise
        self.dhuhr = dhuhr
        self.asr = asr
        self.maghrib = maghrib
        self.isha = isha
    }
    
    public init?(from json: [String: Any]) {
        guard let date = json["date"] as? String,
              let fajr = json["fajr"] as? String,
              let sunrise = json["sunrise"] as? String,
              let dhuhr = json["dhuhr"] as? String,
              let asr = json["asr"] as? String,
              let isha = json["isha"] as? String else {
            return nil
        }
        
        // Handle both 'maghrib' and 'magrib' spellings
        let maghrib = (json["maghrib"] as? String) ?? (json["magrib"] as? String)
        guard let maghrib = maghrib else {
            return nil
        }
        
        self.init(date: date, fajr: fajr, sunrise: sunrise, dhuhr: dhuhr, asr: asr, maghrib: maghrib, isha: isha)
    }
    
    /**
     Parse a time string (HH:mm) into a Date object for the given date components.
     The time string is interpreted as London local time and converted to UTC.
     */
    public func parseTime(_ timeString: String, for dateComponents: DateComponents) -> Date? {
        let parts = timeString.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let year = dateComponents.year,
              let month = dateComponents.month,
              let day = dateComponents.day else {
            return nil
        }
        
        // Create calendar with London timezone to interpret the times correctly
        var londonCalendar = Calendar(identifier: .gregorian)
        guard let londonTimeZone = TimeZone(identifier: "Europe/London") else {
            return nil
        }
        londonCalendar.timeZone = londonTimeZone
        
        // Create date in London timezone (handles GMT/BST automatically)
        let londonDateComponents = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        
        // This returns the Date in UTC, properly accounting for London's timezone offset
        return londonCalendar.date(from: londonDateComponents)
    }
}

/**
 Static lookup service for London prayer times from JSON data.
 */
public class LondonTimesLookup {
    private static var cachedData: [String: Any]? = {
        // Load embedded JSON data automatically
        guard let url = Bundle.module.url(forResource: "LondonPrayerTimes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let jsonDict = json as? [String: Any] else {
            return nil
        }
        return jsonDict
    }()
    
    /**
     Initialize the lookup service with JSON string data.
     This method is kept for backward compatibility but is no longer necessary.
     */
    public static func initialize(with jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw AdhanError.invalidData("Invalid JSON string encoding")
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let jsonDict = json as? [String: Any] else {
                throw AdhanError.invalidData("JSON root must be an object")
            }
            cachedData = jsonDict
        } catch {
            throw AdhanError.invalidData("Failed to parse JSON: \(error.localizedDescription)")
        }
    }
    
    /**
     Initialize the lookup service with pre-parsed JSON data.
     This method is kept for backward compatibility but is no longer necessary.
     */
    public static func initialize(with data: [String: Any]) {
        cachedData = data
    }
    
    /**
     Get London prayer times for a specific date.
     The JSON data is automatically loaded from the embedded resource.
     */
    public static func getTimes(for dateComponents: DateComponents) -> LondonPrayerTimes? {
        guard let data = cachedData else {
            return nil
        }
        
        guard let year = dateComponents.year,
              let month = dateComponents.month,
              let day = dateComponents.day else {
            return nil
        }
        
        let dateString = String(format: "%04d-%02d-%02d", year, month, day)
        
        // Look for times in the expected JSON structure
        if let times = data["times"] as? [String: Any],
           let dayData = times[dateString] as? [String: Any] {
            return LondonPrayerTimes(from: dayData)
        }
        
        return nil
    }
    
    /**
     Clear cached data and reload from embedded resource.
     */
    public static func clearCache() {
        cachedData = nil
        // Reload from embedded resource
        if let url = Bundle.module.url(forResource: "LondonPrayerTimes", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data, options: []),
           let jsonDict = json as? [String: Any] {
            cachedData = jsonDict
        }
    }
}

/**
 Error types for London times lookup.
 */
public enum AdhanError: Error {
    case invalidData(String)
    case missingData(String)
}
