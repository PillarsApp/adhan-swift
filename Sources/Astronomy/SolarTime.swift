//
//  SolarTime.swift
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

struct SolarDay {
    let date: DateComponents
    let observer: Coordinates
    let solar: SolarCoordinates
    let prevSolar: SolarCoordinates
    let nextSolar: SolarCoordinates
    let approxTransit: Double
    let hourAngleCorrection: HourAngleCorrection
    let transitHours: Double

    init(date: DateComponents, coordinates: Coordinates, hourAngleCorrection: HourAngleCorrection) {
        var date = date
        date.hour = 0
        date.minute = 0

        let julianDay = Astronomical.julianDay(dateComponents: date)
        let prevSolar = SolarCoordinates(julianDay: julianDay - 1)
        let solar = SolarCoordinates(julianDay: julianDay)
        let nextSolar = SolarCoordinates(julianDay: julianDay + 1)
        let m0 = Astronomical.approximateTransit(longitude: coordinates.longitudeAngle, siderealTime: solar.apparentSiderealTime, rightAscension: solar.rightAscension,
                                                 correction: hourAngleCorrection)

        self.date = date
        self.observer = coordinates
        self.solar = solar
        self.prevSolar = prevSolar
        self.nextSolar = nextSolar
        self.approxTransit = m0
        self.hourAngleCorrection = hourAngleCorrection
        self.transitHours = Astronomical.correctedTransit(approximateTransit: m0, longitude: coordinates.longitudeAngle, siderealTime: solar.apparentSiderealTime,
                                                          rightAscension: solar.rightAscension, previousRightAscension: prevSolar.rightAscension, nextRightAscension: nextSolar.rightAscension)
    }

    func hoursForSolarAngle(_ angle: Angle, afterTransit: Bool) -> Double {
        return Astronomical.correctedHourAngle(approximateTransit: approxTransit, angle: angle, coordinates: observer, afterTransit: afterTransit, siderealTime: solar.apparentSiderealTime,
                                               rightAscension: solar.rightAscension, previousRightAscension: prevSolar.rightAscension, nextRightAscension: nextSolar.rightAscension,
                                               declination: solar.declination, previousDeclination: prevSolar.declination, nextDeclination: nextSolar.declination,
                                               correction: hourAngleCorrection)
    }

    func afternoonHours(shadowLength: Double) -> Double? {
        let tangent = Angle(fabs(observer.latitude - solar.declination.degrees))
        let inverse = shadowLength + tan(tangent.radians)
        let angle = Angle(radians: atan(1.0 / inverse))

        guard hourAngleCorrection.validatesTimes else {
            let hours = hoursForSolarAngle(angle, afterTransit: true)
            return date.settingHour(hours) == nil ? nil : hours
        }

        let solarAngularDiameter = 32.0 / 60.0
        let discIsFullyAboveTheHorizonAtAsr = angle.degrees > solarAngularDiameter / 2
        guard discIsFullyAboveTheHorizonAtAsr else {
            return nil
        }

        let maxAltitude = Astronomical.altitudeOfCelestialBody(observerLatitude: observer.latitudeAngle, declination: solar.declination, localHourAngle: Angle(0))
        guard maxAltitude.degrees >= angle.degrees else {
            return nil
        }

        let hours = hoursForSolarAngle(angle, afterTransit: true)
        guard let result = date.settingHour(hours),
            let transit = date.settingHour(transitHours),
            let resultDate = Calendar.gregorianUTC.date(from: result),
            let transitDate = Calendar.gregorianUTC.date(from: transit),
            resultDate > transitDate else {
                return nil
        }

        return hours
    }
}

struct SolarTime {
    let day: SolarDay
    let transit: DateComponents
    let sunrise: DateComponents
    let sunset: DateComponents
    private let precision: TimePrecision

    init?(date: DateComponents, coordinates: Coordinates, hourAngleCorrection: HourAngleCorrection = .iterative, precision: TimePrecision = .wholeSeconds) {
        let day = SolarDay(date: date, coordinates: coordinates, hourAngleCorrection: hourAngleCorrection)
        let solarAltitude = Angle(-50.0 / 60.0)
        let sunriseTime = day.hoursForSolarAngle(solarAltitude, afterTransit: false)
        let sunsetTime = day.hoursForSolarAngle(solarAltitude, afterTransit: true)

        guard let transitDate = day.date.settingHour(day.transitHours, precision: precision),
            let sunriseDate = day.date.settingHour(sunriseTime, precision: precision),
            let sunsetDate = day.date.settingHour(sunsetTime, precision: precision) else {
            return nil
        }

        self.day = day
        self.precision = precision
        self.transit = transitDate
        self.sunrise = sunriseDate
        self.sunset = sunsetDate
    }

    func timeForSolarAngle(_ angle: Angle, afterTransit: Bool) -> DateComponents? {
        return day.date.settingHour(day.hoursForSolarAngle(angle, afterTransit: afterTransit), precision: precision)
    }

    func afternoon(shadowLength: Double) -> DateComponents? {
        return afternoonHours(shadowLength: shadowLength).flatMap { day.date.settingHour($0, precision: precision) }
    }

    func afternoonHours(shadowLength: Double) -> Double? {
        return day.afternoonHours(shadowLength: shadowLength)
    }
}
