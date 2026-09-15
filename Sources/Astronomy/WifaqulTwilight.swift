import Foundation

// Implements the explicitly selected variants at wifaqululama.co.uk/highlat/ and /salahtimes/.
// References use raw engine precision: no prayer adjustments or minute rounding enter the cache.
enum WifaqulTwilight {
    private struct Key: Hashable {
        let latitude: Double
        let longitude: Double
        let year: Int
    }

    private struct DawnSeason {
        let precedingDay: Date
        let returningDay: Date
        let offset: TimeInterval
    }

    private struct References {
        var dawnSeasons: [DawnSeason] = []
        var solsticeComputed = false
        var solsticeOffset: TimeInterval?
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [Key: References] = [:]

        func access<T>(key: Key, body: (inout References) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            if entries[key] == nil {
                if entries.count >= 32 { entries.removeAll(keepingCapacity: true) }
                entries[key] = References()
            }
            var references = entries[key] ?? References()
            let result = body(&references)
            entries[key] = references
            return result
        }
    }

    private static let cache = Cache()

    static func calculate(
        date: Date, coordinates: Coordinates, solar: SolarTime,
        sunrise: Date, sunset: Date, tomorrowSunrise: Date,
        options: WifaqulOptions
    ) -> (fajr: Date, isha: Date)? {
        let calendar = Calendar.gregorianUTC
        let midnight = calendar.startOfDay(for: date)
        let key = Key(
            latitude: coordinates.latitude, longitude: coordinates.longitude,
            year: calendar.component(.year, from: midnight))
        let fajr: Date
        if let rawFajr = event(solar, angle: 18, evening: false) {
            fajr = rawFajr
        } else {
            guard coordinates.latitude >= 0 else { return nil }
            switch options.fajrRule {
            case .aqrabulAyyam:
                guard
                    let offset = cache.access(
                        key: key,
                        body: { references in
                            dawnOffset(date: midnight, coordinates: coordinates, references: &references)
                        })
                else { return nil }
                fajr = midnight.addingTimeInterval(offset)
            case .nisfAlLayl:
                guard let previousDate = calendar.date(byAdding: .day, value: -1, to: midnight),
                    let previousSolar = solarTime(previousDate, coordinates: coordinates),
                    let previousSunset = calendar.date(from: previousSolar.sunset)
                else { return nil }
                fajr = previousSunset.addingTimeInterval(sunrise.timeIntervalSince(previousSunset) / 2)
            }
        }

        let northernIsha = coordinates.latitude >= 48
        let rawIsha = event(solar, angle: northernIsha ? 15 : 18, evening: true)
        guard northernIsha else {
            guard let isha = rawIsha else { return nil }
            return (fajr, isha)
        }
        if options.ishaRule == .seventhOfNight, let rawIsha = rawIsha {
            let cap = sunset.addingTimeInterval(tomorrowSunrise.timeIntervalSince(sunset) / 7)
            return (fajr, min(rawIsha, cap))
        }
        guard
            let offset = cache.access(
                key: key,
                body: { references in
                    if !references.solsticeComputed {
                        references.solsticeOffset = solsticeOffset(year: key.year, coordinates: coordinates)
                        references.solsticeComputed = true
                    }
                    return references.solsticeOffset
                })
        else { return nil }
        let cap = midnight.addingTimeInterval(offset + 65 * 60)
        return (fajr, rawIsha.map { min($0, cap) } ?? cap)
    }

    private static func event(_ solar: SolarTime, angle: Double, evening: Bool) -> Date? {
        guard let components = solar.timeForTwilightAngle(Angle(-angle), afterTransit: evening) else { return nil }
        return Calendar.gregorianUTC.date(from: components)
    }

    private static func solarTime(_ date: Date, coordinates: Coordinates) -> SolarTime? {
        SolarTime(
            date: Calendar.gregorianUTC.dateComponents([.year, .month, .day], from: date),
            coordinates: coordinates, preserveSolarDate: true)
    }

    private static func dawnOffset(
        date: Date, coordinates: Coordinates,
        references: inout References
    ) -> TimeInterval? {
        if let season = references.dawnSeasons.first(where: { date > $0.precedingDay && date < $0.returningDay }) {
            return season.offset
        }
        let calendar = Calendar.gregorianUTC
        var preceding: (day: Date, event: Date)?
        var returning: Date?
        for distance in 1...370 {
            guard let day = calendar.date(byAdding: .day, value: -distance, to: date) else { return nil }
            if let solar = solarTime(day, coordinates: coordinates), let dawn = event(solar, angle: 18, evening: false)
            {
                preceding = (day, dawn)
                break
            }
        }
        guard let preceding = preceding else { return nil }
        for distance in 1...370 {
            guard let day = calendar.date(byAdding: .day, value: distance, to: date) else { return nil }
            if let solar = solarTime(day, coordinates: coordinates), event(solar, angle: 18, evening: false) != nil {
                returning = day
                break
            }
        }
        guard let returning = returning else { return nil }
        let offset = preceding.event.timeIntervalSince(preceding.day)
        references.dawnSeasons.append(DawnSeason(precedingDay: preceding.day, returningDay: returning, offset: offset))
        return offset
    }

    private static func solsticeOffset(year: Int, coordinates: Coordinates) -> TimeInterval? {
        let calendar = Calendar.gregorianUTC
        var longestDuration = -Double.infinity
        var sunsetOffset: TimeInterval?
        for day in 15...25 {
            guard let date = calendar.date(from: DateComponents(year: year, month: 6, day: day)),
                let solar = solarTime(date, coordinates: coordinates),
                calendar.date(from: solar.sunrise) != nil,
                let sunset = calendar.date(from: solar.sunset)
            else { return nil }
            let duration = solar.daylightDuration
            if duration > longestDuration {
                longestDuration = duration
                sunsetOffset = sunset.timeIntervalSince(date)
            }
        }
        return sunsetOffset
    }
}
