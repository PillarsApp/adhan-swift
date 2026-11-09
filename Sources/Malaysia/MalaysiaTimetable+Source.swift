//
//  MalaysiaTimetable+Source.swift
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

extension MalaysiaTimetable {
    /// The embedded Malaysian timetable as a published source: authority
    /// `jakim`, one locality per zone in catalog order, wall times in UTC+8.
    public static let source: any OfficialTimetableSource = MalaysiaOfficialSource()
}

struct MalaysiaOfficialSource: OfficialTimetableSource {
    static let columns: [PublishedColumn] = [.imsak, .fajr, .sunrise, .dhuha, .dhuhr, .asr, .maghrib, .isha]
    static let offsetMinutes: Int32 = 480

    let localities: [Locality]
    private let byCode: [String: Locality]

    init() {
        localities = MalaysiaZones.all.map { zone in
            Locality(
                id: LocalityId(zone.code),
                group: zone.state,
                names: ["ms": zone.areas],
                referencePoint: zone.referencePoint,
                validFrom: zone.validFrom,
                validTo: zone.validTo,
                successors: zone.record.successors.map { LocalityId($0) })
        }
        byCode = Dictionary(uniqueKeysWithValues: localities.map { ($0.id.rawValue, $0) })
    }

    var authority: String {
        return "jakim"
    }

    var revision: String {
        return MalaysiaTimetable.revision
    }

    func locality(_ id: LocalityId) -> Locality? {
        return byCode[id.rawValue]
    }

    func localityAt(_ coordinates: Coordinates, on date: DateComponents) throws -> Locality? {
        _ = try OfficialLookupError.day(of: date)
        try OfficialLookupError.check(coordinates)
        return MalaysiaZones.resolve(coordinates, on: date).flatMap { byCode[$0.code] }
    }

    func lookup(_ coordinates: Coordinates, on date: DateComponents, localityId: LocalityId?) throws -> OfficialLookup {
        let day = try OfficialLookupError.day(of: date)
        let zone: MalaysiaZone?
        if let localityId {
            zone = MalaysiaZones.zone(localityId.rawValue)
        } else {
            try OfficialLookupError.check(coordinates)
            zone = MalaysiaZones.resolve(coordinates, on: date)
        }
        guard let zone, let locality = byCode[zone.code] else {
            return .noLocality
        }
        guard let year = date.year,
            let minutes = MalaysiaTimesLookup.shared.row(zone: zone.code, year: year, dayIndex: Int(day - CivilDay.dayNumber(year: Int64(year), month: 1, day: 1))) else {
            return .noRow(locality)
        }
        return .published(OfficialRow(
            locality: locality,
            dayNumber: day,
            authority: authority,
            revision: revision,
            asrShadow: 1,
            columns: MalaysiaOfficialSource.columns,
            minutes: Array(minutes),
            offsetMinutes: MalaysiaOfficialSource.offsetMinutes,
            provenance: .embeddedMalaysia(zone)))
    }
}
