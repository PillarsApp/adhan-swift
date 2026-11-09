//
//  CivilDay.swift
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

enum CivilDay {
    static func isRealDate(year: Int64, month: Int64, day: Int64) -> Bool {
        return (1...12).contains(month) && day >= 1 && day <= daysInMonth(year: year, month: month)
    }

    static func dayNumber(year: Int64, month: Int64, day: Int64) -> Int64 {
        let shifted = month <= 2 ? year - 1 : year
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }

    static func components(ofDay dayNumber: Int64) -> (year: Int64, month: Int64, day: Int64) {
        let shifted = dayNumber + 719468
        let era = (shifted >= 0 ? shifted : shifted - 146096) / 146097
        let dayOfEra = shifted - era * 146097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    static func dayNumber(_ date: DateComponents) -> Int64? {
        guard let year = int32(date.year), let month = int32(date.month), let day = int32(date.day),
            isRealDate(year: year, month: month, day: day) else {
            return nil
        }
        return dayNumber(year: year, month: month, day: day)
    }

    static func date(ofDay dayNumber: Int64) -> DateComponents {
        let civil = components(ofDay: dayNumber)
        return DateComponents(year: Int(civil.year), month: Int(civil.month), day: Int(civil.day))
    }

    static func year(ofDay dayNumber: Int64) -> Int64 {
        return components(ofDay: dayNumber).year
    }

    static func iso(_ dayNumber: Int64) -> String {
        let civil = components(ofDay: dayNumber)
        return padded(civil.year, 4) + "-" + padded(civil.month, 2) + "-" + padded(civil.day, 2)
    }

    static func parse<Bytes: Collection>(_ text: Bytes) -> Int64? where Bytes.Element == UInt8 {
        guard text.count == 10 else {
            return nil
        }
        var digits = [Int64]()
        for (position, byte) in text.enumerated() {
            if position == 4 || position == 7 {
                guard byte == UInt8(ascii: "-") else {
                    return nil
                }
            } else {
                guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
                    return nil
                }
                digits.append(Int64(byte - UInt8(ascii: "0")))
            }
        }
        let year = digits[0] * 1000 + digits[1] * 100 + digits[2] * 10 + digits[3]
        let month = digits[4] * 10 + digits[5]
        let day = digits[6] * 10 + digits[7]
        guard isRealDate(year: year, month: month, day: day) else {
            return nil
        }
        return dayNumber(year: year, month: month, day: day)
    }

    private static func daysInMonth(year: Int64, month: Int64) -> Int64 {
        switch month {
        case 2:
            let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    private static func int32(_ component: Int?) -> Int64? {
        return component.flatMap(Int32.init(exactly:)).map(Int64.init)
    }

    private static func padded(_ value: Int64, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
