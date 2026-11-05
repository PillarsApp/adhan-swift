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

    public let date: DateComponents

    /// Imsak, the end of the pre-dawn meal.
    public let imsak: Date

    /// Subuh, the dawn prayer.
    public let subuh: Date

    /// Syuruk, sunrise.
    public let syuruk: Date

    /// Dhuha, the forenoon prayer.
    public let dhuha: Date

    /// Zohor, the noon prayer.
    public let zohor: Date

    /// Asar, the afternoon prayer as published and corrected, by the Shafi rule.
    public let asar: Date

    /// Maghrib, the sunset prayer.
    public let maghrib: Date

    /// Isyak, the night prayer.
    public let isyak: Date

    public var revision: String {
        return MalaysiaTimetable.revision
    }

    public var source: PrayerTimesSource {
        return .official
    }

    init(zone: MalaysiaZone, day: MalaysiaTimetable.PublishedDay) {
        self.zone = zone
        self.date = day.date
        self.imsak = day.instant(.imsak)
        self.subuh = day.instant(.subuh)
        self.syuruk = day.instant(.syuruk)
        self.dhuha = day.instant(.dhuha)
        self.zohor = day.instant(.zohor)
        self.asar = day.instant(.asar)
        self.maghrib = day.instant(.maghrib)
        self.isyak = day.instant(.isyak)
    }
}

public enum MalaysiaTimetable {
    /// The revision of the embedded data: the first eight hexadecimal digits of
    /// the SHA-256 of the times file, a hyphen, and the same for the zones file.
    public static let revision = "badfebbb-714bce11"

    /// The published row for `zone` on `date`, or nil when the embedded data
    /// has no row for that zone and year, or `date` has no year, month and day.
    public static func day(_ zone: MalaysiaZone, on date: DateComponents) -> MalaysiaDay? {
        guard let day = publishedDay(zone, on: date) else {
            return nil
        }
        return MalaysiaDay(zone: zone, day: day)
    }

    enum Column: Int {
        case imsak, subuh, syuruk, dhuha, zohor, asar, maghrib, isyak
    }

    struct PublishedDay {
        private static let utcOffset: TimeInterval = 8 * 3600

        let date: DateComponents
        let midnight: Date
        let minutes: ArraySlice<UInt16>

        func instant(_ column: Column, plus adjustment: Minute = 0) -> Date {
            let minuteOfDay = Int(minutes[minutes.startIndex + column.rawValue]) + adjustment
            return midnight.addingTimeInterval(minuteOfDay.timeInterval - PublishedDay.utcOffset)
        }
    }

    static func publishedDay(_ zone: MalaysiaZone, on date: DateComponents) -> PublishedDay? {
        let calendar = Calendar.gregorianUTC
        guard let year = date.year, let month = date.month, let day = date.day,
            let midnight = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        let resolved = calendar.dateComponents([.year, .month, .day], from: midnight)
        guard let resolvedYear = resolved.year,
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: midnight),
            let minutes = MalaysiaTimesLookup.shared.row(zone: zone.code, year: resolvedYear, dayIndex: dayOfYear - 1) else {
            return nil
        }
        return PublishedDay(date: resolved, midnight: midnight, minutes: minutes)
    }
}

enum MalaysiaOfficialTimes {
    case official(PrayerTimes.DayResult, MalaysiaZone, MalaysiaDay)
    case noZone
    case noRow(MalaysiaZone)

    static func lookup(coordinates: Coordinates, date: DateComponents, parameters: CalculationParameters) -> MalaysiaOfficialTimes {
        let zone: MalaysiaZone?
        if let code = parameters.malaysiaZone {
            zone = MalaysiaZones.zone(code)
        } else {
            zone = MalaysiaZones.resolve(coordinates, on: date)
        }
        guard let zone else {
            return .noZone
        }
        guard let published = MalaysiaTimetable.publishedDay(zone, on: date) else {
            return .noRow(zone)
        }
        let adjustments = parameters.adjustments
        var asr = adjustments.asr
        if parameters.madhab == .hanafi {
            asr += hanafiShift(on: date, at: zone.referencePoint, hourAngleCorrection: parameters.hourAngleCorrection)
        }
        let times = PrayerTimes.DayResult(
            fajr: published.instant(.subuh, plus: adjustments.fajr),
            sunrise: published.instant(.syuruk, plus: adjustments.sunrise),
            dhuhr: published.instant(.zohor, plus: adjustments.dhuhr),
            asr: published.instant(.asar, plus: asr),
            maghrib: published.instant(.maghrib, plus: adjustments.maghrib),
            isha: published.instant(.isyak, plus: adjustments.isha))
        return .official(times, zone, MalaysiaDay(zone: zone, day: published))
    }

    static func hanafiShift(on date: DateComponents, at coordinates: Coordinates, hourAngleCorrection: HourAngleCorrection) -> Minute {
        guard let solar = SolarTime(date: date, coordinates: coordinates, hourAngleCorrection: hourAngleCorrection),
            let hanafi = solar.afternoonHours(shadowLength: Madhab.hanafi.shadowLength),
            let shafi = solar.afternoonHours(shadowLength: Madhab.shafi.shadowLength) else {
            return 0
        }
        return Int(((hanafi - shafi) * 60).rounded())
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
