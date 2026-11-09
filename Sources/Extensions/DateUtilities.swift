//
//  Date+Extension.swift
//  Adhan
//
//  Copyright © 2018 Batoul Apps. All rights reserved.
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

internal extension Date {

    func roundedToWholeSecondMinute(_ direction: MinuteRounding) -> Date {
        let cal: Calendar = .gregorianUTC
        var components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: self)

        let minute: Double = Double(components.minute ?? 0)
        let second: Double = Double(components.second ?? 0)

        switch direction {
        case .nearest:
            components.minute = Int(minute + round(second/60))
            components.second = 0
        case .up:
            components.minute = Int(minute + ceil(second/60))
            components.second = 0
        case .down:
            components.minute = Int(minute)
            components.second = 0
        case .none:
            components.minute = Int(minute)
            components.second = Int(second)
        }

        return cal.date(from: components) ?? self
    }

    func roundedToMicrosecondMinute(_ direction: MinuteRounding) -> Date {
        let perMinute = Int64.microsecondsPerMinute
        let exact = Int64((timeIntervalSince1970 * 1_000_000).rounded())
        let past = ((exact % perMinute) + perMinute) % perMinute
        let minute = exact - past

        let rounded: Int64
        switch direction {
        case .nearest:
            rounded = past >= perMinute / 2 ? minute + perMinute : minute
        case .up:
            rounded = past > 0 ? minute + perMinute : minute
        case .down:
            rounded = minute
        case .none:
            rounded = exact
        }

        return Date(timeIntervalSince1970: Double(rounded) / 1_000_000)
    }
}

internal extension DateComponents {
    
    func settingHour(_ value: Double, precision: TimePrecision = .wholeSeconds) -> DateComponents? {
        guard value.isNormal else {
            return nil
        }

        if precision == .microseconds {
            return settingMicroseconds(value)
        }
        
        let calculatedHours = floor(value)
        let calculatedMinutes = floor((value - calculatedHours) * 60)
        let calculatedSeconds = floor((value - (calculatedHours + calculatedMinutes/60)) * 60 * 60)
        
        guard let hours = Int32(exactly: calculatedHours),
            let minutes = Int32(exactly: calculatedMinutes),
            let seconds = Int32(exactly: calculatedSeconds) else {
            return nil
        }
        
        var components = self
        components.hour = Int(hours)
        components.minute = Int(minutes)
        components.second = Int(seconds)
        
        return components
    }
}

private extension DateComponents {

    func settingMicroseconds(_ value: Double) -> DateComponents? {
        guard abs(value) < 1_000_000_000,
            let micros = Int64(exactly: floor(value * 3_600_000_000)) else {
            return nil
        }

        let perHour = Int64.microsecondsPerHour
        let perMinute = Int64.microsecondsPerMinute
        let wholeHours = micros / perHour &- (micros % perHour < 0 ? 1 : 0)
        let rest = micros &- wholeHours &* perHour

        var components = self
        components.hour = Int(truncatingIfNeeded: wholeHours)
        components.minute = Int(truncatingIfNeeded: rest / perMinute)
        components.second = Int(truncatingIfNeeded: (rest % perMinute) / 1_000_000)
        components.nanosecond = Int(truncatingIfNeeded: (rest % 1_000_000) &* 1_000)
        return components
    }
}

internal extension Int64 {
    static let microsecondsPerMinute: Int64 = 60_000_000
    static let microsecondsPerHour: Int64 = 3_600_000_000
}

internal extension Calendar {
    
    /// All calculations are done using a gregorian calendar with the UTC timezone
    static let gregorianUTC: Calendar = {
        guard let utc = TimeZone(identifier: "UTC") else {
            fatalError("Unable to instantiate UTC TimeZone.")
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal
    }()
}
