//
//  MalaysiaTimetable.swift
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

/// One day of the official Malaysian timetable for a zone, as published and
/// after the reviewed corrections to it. Every time is a UTC instant, as the
/// times of `PrayerTimes` are.
public struct MalaysiaDay: Sendable {
    public let zone: MalaysiaZone

    let row: OfficialRow

    public var date: DateComponents {
        return row.date
    }

    /// Imsak, the end of the pre-dawn meal.
    public var imsak: Date {
        return row.instant(column: 0)
    }

    /// Subuh, the dawn prayer.
    public var subuh: Date {
        return row.instant(column: 1)
    }

    /// Syuruk, sunrise.
    public var syuruk: Date {
        return row.instant(column: 2)
    }

    /// Dhuha, the forenoon prayer.
    public var dhuha: Date {
        return row.instant(column: 3)
    }

    /// Zohor, the noon prayer.
    public var zohor: Date {
        return row.instant(column: 4)
    }

    /// Asar, the afternoon prayer as published and corrected, by the Shafi rule.
    public var asar: Date {
        return row.instant(column: 5)
    }

    /// Maghrib, the sunset prayer.
    public var maghrib: Date {
        return row.instant(column: 6)
    }

    /// Isyak, the night prayer.
    public var isyak: Date {
        return row.instant(column: 7)
    }

    public var revision: String {
        return MalaysiaTimetable.revision
    }

    public var source: PrayerTimesSource {
        return .official
    }

    init?(row: OfficialRow) {
        guard case .embeddedMalaysia(let zone) = row.provenance else {
            return nil
        }
        self.zone = zone
        self.row = row
    }
}

public enum MalaysiaTimetable {
    /// The revision of the embedded data: the first eight hexadecimal digits of
    /// the SHA-256 of the times file, a hyphen, and the same for the zones file.
    public static let revision = "badfebbb-714bce11"

    /// The published row for `zone` on `date`, or nil when the embedded data
    /// has no row for that zone and year, or `date` has no year, month and day
    /// or is not a calendar day.
    public static func day(_ zone: MalaysiaZone, on date: DateComponents) -> MalaysiaDay? {
        guard case .published(let row)? = try? source.lookup(zone.referencePoint, on: date, localityId: LocalityId(zone.code)) else {
            return nil
        }
        return MalaysiaDay(row: row)
    }
}

enum MalaysiaResources {
    static func bytes(_ name: String) -> [UInt8]? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt"),
            let data = try? Data(contentsOf: url) else {
            return nil
        }
        return [UInt8](data)
    }
}

final class MalaysiaTimesLookup: @unchecked Sendable {
    static let shared = MalaysiaTimesLookup(bytes: MalaysiaResources.bytes("malaysia_times") ?? [])

    let bytes: [UInt8]
    private let lines: [String: Range<Int>]
    private let lock = NSLock()
    private var decoded = [String: MalaysiaZoneYear]()

    init(bytes: [UInt8]) {
        self.bytes = bytes
        var lines = [String: Range<Int>]()
        for range in MalaysiaTimesCodec.lineRanges(bytes) {
            if let header = MalaysiaTimesCodec.header(bytes[range]) {
                lines[header] = range
            }
        }
        self.lines = lines
    }

    func row(zone: String, year: Int, dayIndex: Int) -> ArraySlice<UInt16>? {
        let key = "\(zone) \(year)"
        guard let range = lines[key] else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        if let zoneYear = decoded[key] {
            return zoneYear.day(dayIndex)
        }
        guard let zoneYear = MalaysiaTimesCodec.decodeLine(bytes[range]) else {
            return nil
        }
        decoded[key] = zoneYear
        return zoneYear.day(dayIndex)
    }
}
