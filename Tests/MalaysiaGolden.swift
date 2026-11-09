import Foundation
@testable import Adhan

enum MalaysiaGolden {
    static var offsetSets: [(name: String, minutes: [Int])] { [
        ("zero", [0, 0, 0, 0, 0, 0]),
        ("mixed", [2, -1, 1, -2, 3, -3]),
        ("wide", [-5, 5, -4, 4, -6, 6]),
    ] }

    static var modes: [String] { ["auto", "manual"] }

    static var madhabs: [(name: String, madhab: Madhab)] { [("shafi", .shafi), ("hanafi", .hanafi)] }

    struct Group {
        let key: String
        let lines: [String]

        var digest: String {
            return MalaysiaGolden.fnv1a64Hex(lines.joined(separator: "\n"))
        }
    }

    static func zones() -> [MalaysiaZone] {
        var byCode = [String: MalaysiaZone]()
        for date in [DateComponents(year: 2026, month: 1, day: 1), DateComponents(year: 2027, month: 12, day: 31)] {
            for zone in MalaysiaZones.on(date) {
                byCode[zone.code] = zone
            }
        }
        return byCode.keys.sorted().map { byCode[$0]! }
    }

    static func days() -> [DateComponents] {
        var days = [DateComponents]()
        for year in [2026, 2027] {
            for month in 1...12 {
                for day in 1...daysIn(month: month, year: year) {
                    days.append(DateComponents(year: year, month: month, day: day))
                }
            }
        }
        return days
    }

    static func forEachGroup(_ body: (Group) -> Void) {
        let days = days()
        for zone in zones() {
            for (madhabName, madhab) in madhabs {
                for (offsetName, minutes) in offsetSets {
                    for mode in modes {
                        var lines = [String]()
                        lines.reserveCapacity(days.count)
                        for day in days {
                            var parameters = CalculationMethod.malaysiaOfficial.params
                            parameters.madhab = madhab
                            parameters.adjustments = PrayerAdjustments(
                                fajr: minutes[0], sunrise: minutes[1], dhuhr: minutes[2],
                                asr: minutes[3], maghrib: minutes[4], isha: minutes[5]
                            )
                            if mode == "manual" {
                                parameters.malaysiaZone = zone.code
                            }
                            let times = PrayerTimes(coordinates: zone.referencePoint, date: day, calculationParameters: parameters)
                            lines.append(line(day: day, times: times))
                        }
                        body(Group(key: [zone.code, madhabName, offsetName, mode].joined(separator: "\t"), lines: lines))
                    }
                }
            }
        }
    }

    static func line(day: DateComponents, times: PrayerTimes?) -> String {
        let date = "\(pad(day.year!, 4))-\(pad(day.month!, 2))-\(pad(day.day!, 2))"
        guard let times else {
            return [date, "nil", "nil", "nil", "nil", "nil", "nil", "nil", "nil"].joined(separator: "\t")
        }
        return [
            date,
            sourceName(times.source),
            times.malaysiaZone?.code ?? "-",
            iso(times.fajr),
            iso(times.sunrise),
            iso(times.dhuhr),
            iso(times.asr),
            iso(times.maghrib),
            iso(times.isha),
        ].joined(separator: "\t")
    }

    static func sourceName(_ source: PrayerTimesSource) -> String {
        switch source {
        case .official: return "official"
        case .calculatedNoRow: return "calculatedNoRow"
        case .calculatedNoZone: return "calculatedNoZone"
        case .calculated: return "calculated"
        }
    }

    static func iso(_ time: Date) -> String {
        let totalMillis = Int((time.timeIntervalSince1970 * 1000).rounded())
        let dayMillis = 86_400_000
        var days = totalMillis / dayMillis
        var rest = totalMillis % dayMillis
        if rest < 0 {
            rest += dayMillis
            days -= 1
        }
        let (year, month, day) = civil(fromDays: days)
        let hour = rest / 3_600_000
        let minute = rest / 60_000 % 60
        let second = rest / 1000 % 60
        let millis = rest % 1000
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T\(pad(hour, 2)):\(pad(minute, 2)):\(pad(second, 2)).\(pad(millis, 3))Z"
    }

    static func fnv1a64Hex(_ text: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private static func civil(fromDays days: Int) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }
}
