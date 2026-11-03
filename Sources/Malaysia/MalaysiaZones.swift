//
//  MalaysiaZones.swift
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

public enum MalaysiaZones {
    static let map: MalaysiaZoneMap = {
        guard let bytes = MalaysiaResources.bytes("malaysia_zones"),
            let map = MalaysiaZoneMap.parse(bytes) else {
            return .empty
        }
        return map
    }()

    static let all: [MalaysiaZone] = map.zones.map(MalaysiaZone.init)

    private static let byCode: [String: MalaysiaZone] = {
        var byCode = [String: MalaysiaZone]()
        for zone in all {
            byCode[zone.code] = zone
        }
        return byCode
    }()

    /// The zone in force at `coordinates` on `date`, or nil outside every zone,
    /// for a latitude not within -90...90 or a longitude not within -180...180,
    /// NaN included, and for a date without a year, month and day. A
    /// manual-only zone such as SWK09 is never returned here.
    /// Points up to 3.0 km outside Malaysia's land borders can resolve to a
    /// zone, so a caller that must not serve a neighbouring country should also
    /// check the country.
    public static func resolve(_ coordinates: Coordinates, on date: DateComponents) -> MalaysiaZone? {
        guard abs(coordinates.latitude) <= 90, abs(coordinates.longitude) <= 180, let day = MalaysiaZone.dayNumber(date),
            let code = map.zoneAt(latitude: coordinates.latitude, longitude: coordinates.longitude, day: day) else {
            return nil
        }
        return byCode[code]
    }

    /// Every zone in force on `date`, in catalog order, manual-only zones
    /// included. Empty for a date without a year, month and day.
    public static func on(_ date: DateComponents) -> [MalaysiaZone] {
        return all.filter { $0.inForce(on: date) }
    }

    /// The zone with `code`, whether or not it is still in force, or nil for a
    /// code the data does not know.
    public static func zone(_ code: String) -> MalaysiaZone? {
        return byCode[code]
    }
}
