//
//  DeltaCellsCodec.swift
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

enum DeltaCellsCodec {
    struct Failure: Error {
        let rule: PublishedRule
        let detail: String
    }

    static let maxMinute = 2879

    private static let tilde = UInt8(ascii: "~")
    private static let deltaCells = Array("abcdefg".utf8)

    static func decode<Cells: Collection>(_ cells: Cells, columns: Int) throws -> [UInt16]
    where Cells.Element == UInt8, Cells.Index == Int {
        var minutes = [UInt16]()
        var position = cells.startIndex

        func readHhmm() throws -> UInt16 {
            guard position + 4 <= cells.endIndex else {
                throw Failure(rule: .cellTruncatedTime, detail: "a time is truncated")
            }
            var hour: Int64 = 0
            var minute: Int64 = 0
            for offset in 0..<4 {
                let byte = cells[position + offset]
                guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
                    throw Failure(rule: .cellDigits, detail: "a time is not four digits")
                }
                let digit = Int64(byte - UInt8(ascii: "0"))
                if offset < 2 {
                    hour = hour * 10 + digit
                } else {
                    minute = minute * 10 + digit
                }
            }
            position += 4
            guard minute <= 59 else {
                throw Failure(rule: .cellMinute, detail: "a time has a minute above 59")
            }
            let value = hour * 60 + minute
            guard value <= Int64(maxMinute) else {
                throw Failure(rule: .cellHour, detail: "a time is after 47:59")
            }
            return UInt16(truncatingIfNeeded: value)
        }

        for _ in 0..<columns {
            minutes.append(try readHhmm())
        }
        while position < cells.endIndex {
            let previousDay = minutes.count - columns
            for column in 0..<columns {
                guard position < cells.endIndex else {
                    throw Failure(rule: .cellTruncatedDay, detail: "a day is truncated")
                }
                let cell = cells[position]
                position += 1
                if cell == tilde {
                    minutes.append(try readHhmm())
                } else {
                    guard let index = deltaCells.firstIndex(of: cell) else {
                        throw Failure(rule: .cellLetter, detail: "\(Character(UnicodeScalar(cell))) is not a cell")
                    }
                    let value = Int(minutes[previousDay + column]) + index - 3
                    guard value >= 0, value <= maxMinute else {
                        throw Failure(rule: .cellDelta, detail: "a delta leaves the day")
                    }
                    minutes.append(UInt16(value))
                }
            }
        }
        return minutes
    }
}
