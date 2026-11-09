//
//  PrayerTimes+Official.swift
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

extension PrayerTimes {
    /// Times assembled from a published `row`. `coordinates` is the locality's
    /// reference point.
    ///
    /// The madhab comes from `parameters`. When its shadow factor equals
    /// `row.asrShadow`, Asr is the published Asr. For a Hanafi madhab with a
    /// published `asrHanafi` column, Asr is that column. Otherwise Asr is the
    /// published Asr shifted by the solar difference between the two shadow
    /// factors at the reference point, and the initializer returns nil when
    /// that difference is undefined because the sun does not reach one of the
    /// two shadow lengths there on that day, or because an hour or the
    /// difference in minutes does not fit in 32 bits, which can happen very
    /// near a pole. A day with no sunrise or sunset
    /// still has an Asr when both lengths are reached. `adjustments`, which
    /// default to the adjustments in `parameters`, are added after that.
    /// The method adjustments and rounding in `parameters` are ignored.
    public init?(official row: OfficialRow, parameters: CalculationParameters, adjustments: PrayerAdjustments? = nil) {
        guard let times = PrayerTimes.assembleOfficial(row, parameters: parameters, adjustments: adjustments ?? parameters.adjustments) else {
            return nil
        }
        self.init(times, coordinates: row.locality.referencePoint, date: row.date, calculationParameters: parameters, origin: Origin(official: row))
    }

    static func assembleOfficial(_ row: OfficialRow, parameters: CalculationParameters, adjustments: PrayerAdjustments) -> DayResult? {
        guard let asr = officialAsr(row, parameters: parameters) else {
            return nil
        }
        func at(_ column: PublishedColumn, plus adjustment: Minute) -> Date {
            return row.published(column)!.addingTimeInterval(Double(adjustment) * 60)
        }
        return DayResult(
            fajr: at(.fajr, plus: adjustments.fajr),
            sunrise: at(.sunrise, plus: adjustments.sunrise),
            dhuhr: at(.dhuhr, plus: adjustments.dhuhr),
            asr: asr.addingTimeInterval(Double(adjustments.asr) * 60),
            maghrib: at(.maghrib, plus: adjustments.maghrib),
            isha: at(.isha, plus: adjustments.isha))
    }

    static func officialAsr(_ row: OfficialRow, parameters: CalculationParameters) -> Date? {
        let published = row.published(.asr)!
        let userShadow = parameters.madhab == .hanafi ? 2 : 1
        if userShadow == row.asrShadow {
            return published
        }
        if userShadow == 2, let hanafi = row.published(.asrHanafi) {
            return hanafi
        }
        guard let shift = hanafiShiftMinutes(row, userShadow: userShadow, hourAngleCorrection: parameters.hourAngleCorrection) else {
            return nil
        }
        return published.addingTimeInterval(Double(shift) * 60)
    }

    static func hanafiShiftMinutes(_ row: OfficialRow, userShadow: Int, hourAngleCorrection: HourAngleCorrection) -> Minute? {
        let solar = SolarDay(date: row.date, coordinates: row.locality.referencePoint, hourAngleCorrection: hourAngleCorrection)
        guard let user = solar.afternoonHours(shadowLength: Double(userShadow)),
            let published = solar.afternoonHours(shadowLength: Double(row.asrShadow)) else {
            return nil
        }
        return shiftMinutes(fromHours: user - published)
    }

    @inline(__always)
    static func shiftMinutes(fromHours hours: Double) -> Minute? {
        return Int32(exactly: (hours * 60 + 0.5).rounded(.down)).map(Minute.init)
    }
}
