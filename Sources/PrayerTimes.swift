//
//  PrayerTimes.swift
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

/**
  Prayer times for a location and date using the given calculation parameters.

  All prayer times are in UTC and should be displayed using a DateFormatter that
  has the correct timezone set.

  Near the polar circles the sun may not rise or set, or may not reach the
  angle required for a given prayer, on certain days of the year. By default
  `calculationParameters.polarCircleResolution` is `aqrabBalad`, which
  automatically substitutes the closest usable latitude in these cases. If a
  substitute can't be found (or `polarCircleResolution` is `unresolved`),
  initialization fails and returns nil.
 */
public struct PrayerTimes {
    public let fajr: Date
    public let sunrise: Date
    public let dhuhr: Date
    public let asr: Date
    public let maghrib: Date
    public let isha: Date

    public let coordinates: Coordinates
    public let date: DateComponents
    public let calculationParameters: CalculationParameters

    private let origin: Origin

    enum Origin {
        case calculated
        case calculatedNoZone
        case calculatedNoRow(MalaysiaZone)
        case londonOfficial
        case official(OfficialRow)

        init(official row: OfficialRow) {
            self = .official(row)
        }

        init(calculatedWithout zone: MalaysiaZone?) {
            self = zone.map(Origin.calculatedNoRow) ?? .calculatedNoZone
        }
    }

    /// Where the times came from: `official` for `unifiedLondonTimes` and for a
    /// published row, `calculated` for every other method, and
    /// `calculatedNoZone` or `calculatedNoRow` when `malaysiaOfficial` fell
    /// back to calculating.
    public var source: PrayerTimesSource {
        switch origin {
        case .calculated:
            return .calculated
        case .calculatedNoZone:
            return .calculatedNoZone
        case .calculatedNoRow:
            return .calculatedNoRow
        case .londonOfficial, .official:
            return .official
        }
    }

    /// The official Malaysian zone behind the times when the row came from the
    /// embedded Malaysian timetable, or the zone `malaysiaOfficial` would have
    /// read when it fell back to calculating: the manual zone when
    /// `CalculationParameters.malaysiaZone` is set, else the zone resolved from
    /// the coordinates. Nil for every other row and method, for a manual code
    /// the data does not know and outside every zone.
    public var malaysiaZone: MalaysiaZone? {
        switch origin {
        case .calculatedNoRow(let zone):
            return zone
        case .official(let row):
            guard case .embeddedMalaysia(let zone) = row.provenance else {
                return nil
            }
            return zone
        case .calculated, .calculatedNoZone, .londonOfficial:
            return nil
        }
    }

    /// The published row behind the times, before adjustments and the Hanafi
    /// shift. Nil unless the row came from the embedded Malaysian timetable,
    /// so `PrayerTimes(official:)` on a `MalaysiaTimetable.source` row reports
    /// it as `malaysiaOfficial` does.
    public var malaysiaDay: MalaysiaDay? {
        guard case .official(let row) = origin else {
            return nil
        }
        return MalaysiaDay(row: row)
    }

    /// The published row behind official times, before adjustments and the
    /// Hanafi shift. Nil for calculated times and for the London lookup.
    public var officialRow: OfficialRow? {
        switch origin {
        case .official(let row):
            return row
        case .calculated, .calculatedNoZone, .calculatedNoRow, .londonOfficial:
            return nil
        }
    }

    init(_ times: DayResult, coordinates: Coordinates, date: DateComponents, calculationParameters: CalculationParameters, origin: Origin) {
        self.fajr = times.fajr
        self.sunrise = times.sunrise
        self.dhuhr = times.dhuhr
        self.asr = times.asr
        self.maghrib = times.maghrib
        self.isha = times.isha
        self.coordinates = coordinates
        self.date = date
        self.calculationParameters = calculationParameters
        self.origin = origin
    }

    public init?(coordinates: Coordinates, date: DateComponents, calculationParameters: CalculationParameters) {

        // Special handling for London lookup times
        if calculationParameters.method == .unifiedLondonTimes {
            guard let londonTimes = Self.initializeFromLondonLookup(date: date, calculationParameters: calculationParameters) else {
                return nil
            }
            self.init(londonTimes, coordinates: coordinates, date: date, calculationParameters: calculationParameters, origin: .londonOfficial)
            return
        }
        guard date.year != nil,
            date.month != nil,
            date.day != nil,
            date.isValidDate(in: .gregorianUTC) else {
            return nil
        }

        var origin = Origin.calculated
        if calculationParameters.method == .malaysiaOfficial {
            do {
                switch try MalaysiaTimetable.source.lookup(coordinates, on: date, localityId: calculationParameters.malaysiaZone.map { LocalityId($0) }) {
                case .published(let row):
                    if let times = PrayerTimes.assembleOfficial(row, parameters: calculationParameters, adjustments: calculationParameters.adjustments) {
                        self.init(times, coordinates: coordinates, date: date, calculationParameters: calculationParameters, origin: Origin(official: row))
                        return
                    }
                    origin = Origin(calculatedWithout: MalaysiaZones.zone(row.locality.id.rawValue))
                case .noLocality:
                    origin = .calculatedNoZone
                case .noRow(let locality):
                    origin = Origin(calculatedWithout: MalaysiaZones.zone(locality.id.rawValue))
                }
            } catch {
                if let code = calculationParameters.malaysiaZone {
                    origin = Origin(calculatedWithout: MalaysiaZones.zone(code))
                } else {
                    origin = Origin(calculatedWithout: MalaysiaZones.resolve(coordinates, on: date))
                }
            }
        }

        guard abs(coordinates.latitude) <= 90 else {
            return nil
        }

        // Compute times for the requested location and date. This only fails near the
        // polar circles during extreme situations like midnight sun or polar night.
        var result = PrayerTimes.computeForDay(coordinates: coordinates, date: date, calculationParameters: calculationParameters)

        // If the initial calculation failed, attempt polar circle resolution.
        // aqrabBalad uses the nearest latitude that works,
        // aqrabYaum uses the nearest day that works,
        // and unresolved leaves the result nil.
        if result == nil {
            result = calculationParameters.polarCircleResolution.resolve(coordinates: coordinates, date: date, calculationParameters: calculationParameters)
        }

        // Prayer times can't be determined for this location and date. Either
        // polarCircleResolution is unresolved or was unable to find valid times
        // for the given parameters.
        guard let result else {
            return nil
        }

        self.init(result, coordinates: coordinates, date: date, calculationParameters: calculationParameters, origin: origin)
    }

    /// Prayer times computed for a single day of solar geometry
    struct DayResult: Equatable {
        let fajr: Date
        let sunrise: Date
        let dhuhr: Date
        let asr: Date
        let maghrib: Date
        let isha: Date

        /// Shifts every time by a whole number of calendar days. Used to relabel a polar
        /// circle resolved result onto the originally requested date.
        func shifted(byDays days: Int) -> DayResult? {
            guard days != 0 else {
                return self
            }

            let cal: Calendar = .gregorianUTC
            guard let fajr = cal.date(byAdding: .day, value: days, to: fajr),
                let sunrise = cal.date(byAdding: .day, value: days, to: sunrise),
                let dhuhr = cal.date(byAdding: .day, value: days, to: dhuhr),
                let asr = cal.date(byAdding: .day, value: days, to: asr),
                let maghrib = cal.date(byAdding: .day, value: days, to: maghrib),
                let isha = cal.date(byAdding: .day, value: days, to: isha) else {
                return nil
            }

            return DayResult(fajr: fajr, sunrise: sunrise, dhuhr: dhuhr, asr: asr, maghrib: maghrib, isha: isha)
        }
    }

    /// Computes prayer times for a single day of solar geometry with no awareness of
    /// polar circle resolution. Returns nil if any time can't be computed or, under
    /// `.iterative`, the times end up out of order.
    static func computeForDay(
        coordinates: Coordinates,
        date: DateComponents,
        calculationParameters: CalculationParameters
    ) -> DayResult? {

        var tempFajr: Date? = nil
        var tempSunrise: Date? = nil
        var tempDhuhr: Date? = nil
        var tempAsr: Date? = nil
        var tempMaghrib: Date? = nil
        var tempIsha: Date? = nil
        let cal: Calendar = .gregorianUTC

        guard let prayerDate = cal.date(from: date),
            let tomorrowDate = cal.date(byAdding: .day, value: 1, to: prayerDate),
            let year = date.year,
            let dayOfYear = cal.ordinality(of: .day, in: .year, for: prayerDate) else {
            return nil
        }

        let tomorrow = cal.dateComponents([.year, .month, .day], from: tomorrowDate)

        let hourAngleCorrection = calculationParameters.hourAngleCorrection
        let rule = RoundingRule(calculationParameters.rounding)

        guard let solarTime = SolarTime(date: date, coordinates: coordinates, hourAngleCorrection: hourAngleCorrection, precision: rule.precision),
            let tomorrowSolarTime = SolarTime(date: tomorrow, coordinates: coordinates, hourAngleCorrection: hourAngleCorrection, precision: rule.precision),
            let sunriseDate = cal.date(from: solarTime.sunrise),
            let sunsetDate = cal.date(from: solarTime.sunset),
            let tomorrowSunrise = cal.date(from: tomorrowSolarTime.sunrise) else {
                // unable to determine transit, sunrise or sunset aborting calculations
                return nil
        }

        tempSunrise = cal.date(from: solarTime.sunrise)
        tempMaghrib = cal.date(from: solarTime.sunset)
        tempDhuhr = cal.date(from: solarTime.transit)

        if let asrComponents = solarTime.afternoon(shadowLength: calculationParameters.madhab.shadowLength) {
            tempAsr = cal.date(from: asrComponents)
        }

        // get night length
        let night = tomorrowSunrise.timeIntervalSince(sunsetDate)

        if let fajrComponents = solarTime.timeForSolarAngle(Angle(-calculationParameters.fajrAngle), afterTransit: false) {
            tempFajr = cal.date(from: fajrComponents)
        }

        // special case for moonsighting committee at or above latitude 55
        if calculationParameters.method == .moonsightingCommittee && coordinates.latitude >= 55 {
            let nightFraction = night / 7
            tempFajr = sunriseDate.addingTimeInterval(-nightFraction)
        }

        let safeFajr: Date = {
            guard calculationParameters.method != .moonsightingCommittee else {
                return Astronomical.seasonAdjustedMorningTwilight(latitude: coordinates.latitude, day: dayOfYear, year: year, sunrise: sunriseDate)
            }

            let portion = calculationParameters.nightPortions(using: coordinates).fajr
            let nightFraction = portion * night

            return sunriseDate.addingTimeInterval(-nightFraction)
        }()

        if tempFajr == nil || tempFajr?.compare(safeFajr) == .orderedAscending
            || (hourAngleCorrection.validatesTimes && !PrayerTimes.timesInOrder(tempFajr, tempSunrise)) {
            tempFajr = safeFajr
        }

        // Isha calculation with check against safe value
        if calculationParameters.ishaInterval > 0 {
            tempIsha = tempMaghrib?.addingTimeInterval(calculationParameters.ishaInterval.timeInterval)
        } else {
            if let ishaComponents = solarTime.timeForSolarAngle(Angle(-calculationParameters.ishaAngle), afterTransit: true) {
                tempIsha = cal.date(from: ishaComponents)
            }

            // special case for moonsighting committee at or above latitude 55
            if calculationParameters.method == .moonsightingCommittee && coordinates.latitude >= 55 {
                let nightFraction = night / 7
                tempIsha = sunsetDate.addingTimeInterval(nightFraction)
            }

            let safeIsha: Date = {
                guard calculationParameters.method != .moonsightingCommittee else {
                    return Astronomical.seasonAdjustedEveningTwilight(latitude: coordinates.latitude, day: dayOfYear, year: year, sunset: sunsetDate, shafaq: calculationParameters.shafaq)
                }

                let portion = calculationParameters.nightPortions(using: coordinates).isha
                let nightFraction = portion * night

                return sunsetDate.addingTimeInterval(nightFraction)
            }()

            if tempIsha == nil || (hourAngleCorrection.validatesTimes && !PrayerTimes.timesInOrder(tempMaghrib, tempIsha))
                || tempIsha?.compare(safeIsha) == .orderedDescending {
                tempIsha = safeIsha
            }
        }
        
        // Maghrib calculation with check against safe value
        if let maghribAngle = calculationParameters.maghribAngle,
            let maghribComponents = solarTime.timeForSolarAngle(Angle(-maghribAngle), afterTransit: true),
            let maghribDate = cal.date(from: maghribComponents),
            // maghrib is considered safe if it falls between sunset and isha
            sunsetDate < maghribDate, (tempIsha?.compare(maghribDate) == .orderedDescending || tempIsha == nil) {
                tempMaghrib = maghribDate
        }

        // Ensure all prayer times are in the correct order and that there is
        // at least a 5 minute time difference. This prevents invalid prayer times
        // for locations inside the polar circle on dates where the sun rises
        // but never leaves the horizon.
        if hourAngleCorrection.validatesTimes {
            guard PrayerTimes.timesInOrder(tempFajr, tempSunrise),
                PrayerTimes.timesInOrder(tempSunrise, tempDhuhr),
                PrayerTimes.timesInOrder(tempDhuhr, tempAsr),
                PrayerTimes.timesInOrder(tempAsr, tempMaghrib),
                PrayerTimes.timesInOrder(tempMaghrib, tempIsha) else {
                    return nil
            }
        }

        // if we don't have all prayer times then initialization failed
        guard let fajr = tempFajr,
            let sunrise = tempSunrise,
            let dhuhr = tempDhuhr,
            let asr = tempAsr,
            let maghrib = tempMaghrib,
            let isha = tempIsha else {
                return nil
        }

        // Apply all offsets and rounding to the final times
        return DayResult(
            fajr: rule.roundedStart(fajr.addingTimeInterval(calculationParameters.adjustments.fajr.timeInterval)
                .addingTimeInterval(calculationParameters.methodAdjustments.fajr.timeInterval)),
            sunrise: rule.roundedSunrise(sunrise.addingTimeInterval(calculationParameters.adjustments.sunrise.timeInterval)
                .addingTimeInterval(calculationParameters.methodAdjustments.sunrise.timeInterval)),
            dhuhr: rule.roundedStart(dhuhr.addingTimeInterval(calculationParameters.adjustments.dhuhr.timeInterval)
                .addingTimeInterval(calculationParameters.methodAdjustments.dhuhr.timeInterval)),
            asr: rule.roundedStart(asr.addingTimeInterval(calculationParameters.adjustments.asr.timeInterval)
                .addingTimeInterval(calculationParameters.methodAdjustments.asr.timeInterval)),
            maghrib: rule.roundedStart(maghrib.addingTimeInterval(calculationParameters.adjustments.maghrib.timeInterval)
                .addingTimeInterval(calculationParameters.methodAdjustments.maghrib.timeInterval)),
            isha: rule.roundedStart(isha.addingTimeInterval(calculationParameters.adjustments.isha.timeInterval)
                .addingTimeInterval(calculationParameters.methodAdjustments.isha.timeInterval)))
    }

    public func currentPrayer(at time: Date = Date()) -> Prayer? {
        if isha.timeIntervalSince(time) <= 0 {
            return .isha
        } else if maghrib.timeIntervalSince(time) <= 0 {
            return .maghrib
        } else if asr.timeIntervalSince(time) <= 0 {
            return .asr
        } else if dhuhr.timeIntervalSince(time) <= 0 {
            return .dhuhr
        } else if sunrise.timeIntervalSince(time) <= 0 {
            return .sunrise
        } else if fajr.timeIntervalSince(time) <= 0 {
            return .fajr
        }

        return nil
    }

    public func nextPrayer(at time: Date = Date()) -> Prayer? {
        if isha.timeIntervalSince(time) <= 0 {
            return nil
        } else if maghrib.timeIntervalSince(time) <= 0 {
            return .isha
        } else if asr.timeIntervalSince(time) <= 0 {
            return .maghrib
        } else if dhuhr.timeIntervalSince(time) <= 0 {
            return .asr
        } else if sunrise.timeIntervalSince(time) <= 0 {
            return .dhuhr
        } else if fajr.timeIntervalSince(time) <= 0 {
            return .sunrise
        }

        return .fajr
    }

    public func time(for prayer: Prayer) -> Date {
        switch prayer {
        case .fajr:
            return fajr
        case .sunrise:
            return sunrise
        case .dhuhr:
            return dhuhr
        case .asr:
            return asr
        case .maghrib:
            return maghrib
        case .isha:
            return isha
        }
    }
    
    private static func initializeFromLondonLookup(date: DateComponents, calculationParameters: CalculationParameters) -> DayResult? {
        guard let londonTimes = LondonTimesLookup.getTimes(for: date) else {
            return nil
        }
        
        guard let tempFajr = londonTimes.parseTime(londonTimes.fajr, for: date),
              let tempSunrise = londonTimes.parseTime(londonTimes.sunrise, for: date),
              let tempDhuhr = londonTimes.parseTime(londonTimes.dhuhr, for: date),
              let tempAsr = londonTimes.parseTime(londonTimes.asr, for: date),
              let tempMaghrib = londonTimes.parseTime(londonTimes.maghrib, for: date),
              let tempIsha = londonTimes.parseTime(londonTimes.isha, for: date) else {
            return nil
        }
        
        // Apply adjustments and rounding (same as astronomical calculations)
        let rule = RoundingRule(calculationParameters.rounding)
        let fajr = rule.roundedStart(tempFajr
            .addingTimeInterval(calculationParameters.adjustments.fajr.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.fajr.timeInterval))
        
        let sunrise = rule.roundedSunrise(tempSunrise
            .addingTimeInterval(calculationParameters.adjustments.sunrise.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.sunrise.timeInterval))
        
        let dhuhr = rule.roundedStart(tempDhuhr
            .addingTimeInterval(calculationParameters.adjustments.dhuhr.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.dhuhr.timeInterval))
        
        let asr = rule.roundedStart(tempAsr
            .addingTimeInterval(calculationParameters.adjustments.asr.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.asr.timeInterval))
        
        let maghrib = rule.roundedStart(tempMaghrib
            .addingTimeInterval(calculationParameters.adjustments.maghrib.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.maghrib.timeInterval))
        
        let isha = rule.roundedStart(tempIsha
            .addingTimeInterval(calculationParameters.adjustments.isha.timeInterval)
            .addingTimeInterval(calculationParameters.methodAdjustments.isha.timeInterval))
        
        return DayResult(fajr: fajr, sunrise: sunrise, dhuhr: dhuhr, asr: asr, maghrib: maghrib, isha: isha)
    }

    static let minimumPrayerGap: TimeInterval = 5 * 60

    static func timesInOrder(_ first: Date?, _ second: Date?) -> Bool {
        guard let first = first, let second = second else {
            return false
        }

        return second.timeIntervalSince(first) >= PrayerTimes.minimumPrayerGap
    }
}
