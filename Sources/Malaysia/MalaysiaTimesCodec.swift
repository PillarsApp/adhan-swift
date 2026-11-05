//
//  MalaysiaTimesCodec.swift
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

struct MalaysiaZoneYear {
    let zone: String
    let year: Int
    let minutes: [UInt16]

    var dayCount: Int {
        return minutes.count / MalaysiaTimesCodec.fieldCount
    }

    func day(_ index: Int) -> ArraySlice<UInt16>? {
        let start = index * MalaysiaTimesCodec.fieldCount
        guard index >= 0, start + MalaysiaTimesCodec.fieldCount <= minutes.count else {
            return nil
        }
        return minutes[start..<(start + MalaysiaTimesCodec.fieldCount)]
    }
}

enum MalaysiaTimesCodec {
    static let fieldCount = 8

    private static let space = UInt8(ascii: " ")
    private static let newline = UInt8(ascii: "\n")
    private static let tilde = UInt8(ascii: "~")
    private static let deltaCells = Array("abcdefg".utf8)
    private static let minutesInDay = 1440

    static func decode(_ text: [UInt8]) -> [MalaysiaZoneYear]? {
        var zoneYears = [MalaysiaZoneYear]()
        for range in lineRanges(text) {
            guard let zoneYear = decodeLine(text[range]) else {
                return nil
            }
            zoneYears.append(zoneYear)
        }
        return zoneYears
    }

    static func lineRanges(_ text: [UInt8]) -> [Range<Int>] {
        var ranges = [Range<Int>]()
        var start = 0
        while start < text.count {
            let end = text[start...].firstIndex(of: newline) ?? text.count
            if end > start {
                ranges.append(start..<end)
            }
            start = end + 1
        }
        return ranges
    }

    static func header(_ line: ArraySlice<UInt8>) -> String? {
        guard let firstSpace = line.firstIndex(of: space),
            let secondSpace = line[(firstSpace + 1)...].firstIndex(of: space) else {
            return nil
        }
        return String(decoding: line[line.startIndex..<secondSpace], as: UTF8.self)
    }

    static func decodeLine(_ line: ArraySlice<UInt8>) -> MalaysiaZoneYear? {
        let parts = line.split(separator: space, omittingEmptySubsequences: false)
        guard parts.count == 3,
            let year = Int(String(decoding: parts[1], as: UTF8.self)),
            let minutes = decodeDays(parts[2]) else {
            return nil
        }
        return MalaysiaZoneYear(zone: String(decoding: parts[0], as: UTF8.self), year: year, minutes: minutes)
    }

    private static func decodeDays(_ data: ArraySlice<UInt8>) -> [UInt16]? {
        var minutes = [UInt16]()
        var position = data.startIndex

        func readHhmm() -> UInt16? {
            guard position + 4 <= data.endIndex else {
                return nil
            }
            var value = 0
            for byte in data[position..<(position + 4)] {
                guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
                    return nil
                }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            position += 4
            return UInt16((value / 100) * 60 + value % 100)
        }

        for _ in 0..<fieldCount {
            guard let value = readHhmm() else {
                return nil
            }
            minutes.append(value)
        }
        while position < data.endIndex {
            let previousDay = minutes.count - fieldCount
            for column in 0..<fieldCount {
                guard position < data.endIndex else {
                    return nil
                }
                let cell = data[position]
                position += 1
                if cell == tilde {
                    guard let value = readHhmm() else {
                        return nil
                    }
                    minutes.append(value)
                } else {
                    guard let index = deltaCells.firstIndex(of: cell) else {
                        return nil
                    }
                    let value = Int(minutes[previousDay + column]) + index - 3
                    guard value >= 0, value < minutesInDay else {
                        return nil
                    }
                    minutes.append(UInt16(value))
                }
            }
        }
        return minutes
    }
}
