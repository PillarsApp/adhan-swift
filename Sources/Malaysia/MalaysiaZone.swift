//
//  MalaysiaZone.swift
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

public struct MalaysiaZone: Hashable, Sendable, CustomStringConvertible {
    let record: MalaysiaZoneRecord

    init(record: MalaysiaZoneRecord) {
        self.record = record
    }

    /// The zone code, such as WLY01. e-Solat publishes it, except for the nine
    /// Selangor district zones, whose codes are provisional because JAKIM has
    /// not published any.
    public var code: String {
        return record.code
    }

    public var state: String {
        return record.state
    }

    public var areas: String {
        return record.areas
    }

    /// The first day the zone is in force, or nil when it has always been.
    public var validFrom: DateComponents? {
        return record.validFromDay == MalaysiaZoneRecord.alwaysInForceFrom ? nil : MalaysiaZone.date(record.validFromDay)
    }

    /// The last day the zone is in force, or nil when it has no end.
    public var validTo: DateComponents? {
        return record.validToDay == MalaysiaZoneRecord.alwaysInForceTo ? nil : MalaysiaZone.date(record.validToDay)
    }

    /// The GeoNames position of the zone's first named town, or the centre of
    /// its special area, such as a summit, a hill, an island or a pass. The
    /// Hanafi shift of Asr is calculated here. It need not resolve to this
    /// zone: the point of SWK09, which has no geometry, resolves to SWK01.
    public var referencePoint: Coordinates {
        return Coordinates(latitude: record.referenceLatitude, longitude: record.referenceLongitude)
    }

    /// The zones that replace this one after `validTo`, empty for a zone still
    /// in force.
    public var successors: [MalaysiaZone] {
        return record.successors.compactMap(MalaysiaZones.zone)
    }

    /// Whether this zone is in force on `date`. False for a date without a
    /// year, month and day, or with a year, month or day outside the 32-bit
    /// range.
    public func inForce(on date: DateComponents) -> Bool {
        guard let day = MalaysiaZone.dayNumber(date) else {
            return false
        }
        return record.inForce(day)
    }

    public var description: String {
        return "MalaysiaZone(\(code))"
    }

    public static func == (lhs: MalaysiaZone, rhs: MalaysiaZone) -> Bool {
        return lhs.code == rhs.code
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }

    static func dayNumber(_ date: DateComponents) -> Int64? {
        guard let year = overflowSafe(date.year), let month = overflowSafe(date.month), let day = overflowSafe(date.day) else {
            return nil
        }
        return year * 10000 + month * 100 + day
    }

    private static func overflowSafe(_ component: Int?) -> Int64? {
        return component.flatMap(Int32.init(exactly:)).map(Int64.init)
    }

    private static func date(_ yyyymmdd: Int64) -> DateComponents {
        return DateComponents(year: Int(yyyymmdd / 10000), month: Int(yyyymmdd / 100 % 100), day: Int(yyyymmdd % 100))
    }
}
