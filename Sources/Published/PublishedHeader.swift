//
//  PublishedHeader.swift
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

struct ZoneOffsets {
    let days: [Int64]
    let minutes: [Int32]

    func offset(on day: Int64) -> Int32 {
        var offset = minutes[0]
        for index in 1..<days.count where days[index] <= day {
            offset = minutes[index]
        }
        return offset
    }
}

struct PublishedHeader {
    let authority: String
    let revision: Int32
    let part: String
    let firstDay: Int64
    let lastDay: Int64
    let columns: [PublishedColumn]
    let coreIndices: [Int]
    let asrShadow: Int
    let zones: [ZoneOffsets]
    let localities: [LocalityRecord]
    let localityIndex: [[UInt8]: Int]

    var coverage: (from: DateComponents, to: DateComponents) {
        return (CivilDay.date(ofDay: firstDay), CivilDay.date(ofDay: lastDay))
    }

    static func parse(_ json: Data) throws -> PublishedHeader {
        let root = try HeaderJSON.parse([UInt8](json))
        let authority = try token(try required(root, "authority"), "authority", .headerAuthority)
        let revision = try int32(try required(root, "revision"), "revision", .headerRevision)
        guard revision >= 0 else {
            throw PublishedTimetable.FormatError(.headerRevision, "revision is negative")
        }
        let part = try token(try required(root, "part"), "part", .headerPart)
        let coverage = try strings(try required(root, "coverage"), "coverage", .headerCoverage)
        guard coverage.count == 2 else {
            throw PublishedTimetable.FormatError(.headerCoverage, "coverage is not [from, to]")
        }
        let firstDay = try day(coverage[0], "coverage start", .headerCoverage)
        let lastDay = try day(coverage[1], "coverage end", .headerCoverage)
        guard firstDay <= lastDay else {
            throw PublishedTimetable.FormatError(.headerCoverageOrder, "coverage ends before it starts")
        }
        var columns = [PublishedColumn]()
        for name in try strings(try required(root, "columns"), "columns", .columnUnknown) {
            guard let column = PublishedColumn(rawValue: name) else {
                throw PublishedTimetable.FormatError(.columnUnknown, "\(name) is not a column name")
            }
            guard !columns.contains(column) else {
                throw PublishedTimetable.FormatError(.columnDuplicate, "\(name) appears twice in columns")
            }
            columns.append(column)
        }
        for column in PublishedColumn.allCases where column.isCore && !columns.contains(column) {
            throw PublishedTimetable.FormatError(.columnMissingCore, "columns lacks \(column.rawValue)")
        }
        let asrShadow = try int32(try required(root, "asrShadow"), "asrShadow", .headerAsrShadow)
        guard asrShadow == 1 || asrShadow == 2 else {
            throw PublishedTimetable.FormatError(.headerAsrShadow, "asrShadow is not 1 or 2")
        }
        let zonesJSON = try array(try required(root, "zones"), "zones", .zonesEmpty)
        guard !zonesJSON.isEmpty else {
            throw PublishedTimetable.FormatError(.zonesEmpty, "zones is empty")
        }
        var zoneIds = Set<[UInt8]>()
        for zone in zonesJSON {
            let id = try string(try required(try object(zone, "a zone", .zoneId), "id"), "a zone id", .zoneId)
            guard !id.isEmpty else {
                throw PublishedTimetable.FormatError(.zoneId, "a zone id is empty")
            }
            guard zoneIds.insert(Array(id.utf8)).inserted else {
                throw PublishedTimetable.FormatError(.zoneIdDuplicate, "zone id \(id) is duplicated")
            }
        }
        let zones = try zonesJSON.map { try offsets($0, coverageStart: firstDay) }
        let localitiesJSON = try array(try required(root, "localities"), "localities", .localitiesEmpty)
        guard !localitiesJSON.isEmpty else {
            throw PublishedTimetable.FormatError(.localitiesEmpty, "localities is empty")
        }
        var ids = Set<[UInt8]>()
        for locality in localitiesJSON {
            let id = try string(try required(try object(locality, "a locality", .localityId), "id"), "a locality id", .localityId)
            guard isLocalityId(id) else {
                throw PublishedTimetable.FormatError(.localityId, "locality id \"\(id)\" is malformed")
            }
            guard ids.insert(Array(id.utf8)).inserted else {
                throw PublishedTimetable.FormatError(.localityIdDuplicate, "locality id \(id) is duplicated")
            }
        }
        let localities = try localitiesJSON.map { try record($0, ids: ids, zoneCount: zones.count) }
        var localityIndex = [[UInt8]: Int]()
        for (index, record) in localities.enumerated() {
            localityIndex[Array(record.locality.id.rawValue.utf8)] = index
        }
        return PublishedHeader(
            authority: authority,
            revision: revision,
            part: part,
            firstDay: firstDay,
            lastDay: lastDay,
            columns: columns,
            coreIndices: PublishedColumn.allCases.filter { $0.isCore }.compactMap { columns.firstIndex(of: $0) },
            asrShadow: Int(asrShadow),
            zones: zones,
            localities: localities,
            localityIndex: localityIndex)
    }

    private static func required(_ object: HeaderJSON, _ key: String) throws -> HeaderJSON {
        guard let value = object[key] else {
            throw PublishedTimetable.FormatError(.headerKeyAbsent, "\(key) is absent")
        }
        return value
    }

    private static func object(_ value: HeaderJSON, _ what: String, _ rule: PublishedRule) throws -> HeaderJSON {
        guard case .object = value else {
            throw PublishedTimetable.FormatError(rule, "\(what) is \(value.typeName), not an object")
        }
        return value
    }

    private static func array(_ value: HeaderJSON, _ what: String, _ rule: PublishedRule) throws -> [HeaderJSON] {
        guard case .array(let values) = value else {
            throw PublishedTimetable.FormatError(rule, "\(what) is \(value.typeName), not an array")
        }
        return values
    }

    private static func string(_ value: HeaderJSON, _ what: String, _ rule: PublishedRule) throws -> String {
        guard case .string(let text) = value else {
            throw PublishedTimetable.FormatError(rule, "\(what) is \(value.typeName), not a string")
        }
        return text
    }

    private static func strings(_ value: HeaderJSON, _ what: String, _ rule: PublishedRule) throws -> [String] {
        return try array(value, what, rule).map { try string($0, "an element of \(what)", rule) }
    }

    private static func int32(_ value: HeaderJSON, _ what: String, _ rule: PublishedRule) throws -> Int32 {
        guard case .number(let text) = value else {
            throw PublishedTimetable.FormatError(rule, "\(what) is \(value.typeName), not an integer")
        }
        let isInteger = !text.utf8.contains { $0 == UInt8(ascii: ".") || $0 == UInt8(ascii: "e") || $0 == UInt8(ascii: "E") }
        guard isInteger, let wide = Int64(text), let narrow = Int32(exactly: wide) else {
            throw PublishedTimetable.FormatError(rule, "\(what) is not a 32-bit integer")
        }
        return narrow
    }

    private static func token(_ value: HeaderJSON, _ what: String, _ rule: PublishedRule) throws -> String {
        let text = try string(value, what, rule)
        guard !text.isEmpty else {
            throw PublishedTimetable.FormatError(rule, "\(what) is empty")
        }
        let bytes = Array(text.utf8)
        let fits = bytes.count <= 64 && bytes[0] != UInt8(ascii: "-") && bytes.allSatisfy { byte in
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) || byte == UInt8(ascii: "-")
        }
        guard fits else {
            throw PublishedTimetable.FormatError(rule, "\(what) does not match ^[a-z0-9][a-z0-9-]{0,63}$")
        }
        return text
    }

    private static func day(_ text: String, _ what: String, _ rule: PublishedRule) throws -> Int64 {
        guard let day = CivilDay.parse(Array(text.utf8)) else {
            throw PublishedTimetable.FormatError(rule, "\(what) is not a YYYY-MM-DD calendar day")
        }
        return day
    }

    private static func isLocalityId(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        return (1...32).contains(bytes.count) && bytes.allSatisfy { byte in
            (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) || byte == UInt8(ascii: "_") || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "-")
        }
    }

    private static func offsets(_ zone: HeaderJSON, coverageStart: Int64) throws -> ZoneOffsets {
        let id = try string(try required(zone, "id"), "a zone id", .zoneId)
        let entries = try array(try required(zone, "offsets"), "offsets of \(id)", .zoneOffsetsEmpty)
        guard !entries.isEmpty else {
            throw PublishedTimetable.FormatError(.zoneOffsetsEmpty, "offsets of \(id) is empty")
        }
        var days = [Int64]()
        var minutes = [Int32]()
        for entry in entries {
            let pair = try array(entry, "an offset of \(id)", .zoneOffsetShape)
            guard pair.count == 2, case .string(let date) = pair[0] else {
                throw PublishedTimetable.FormatError(.zoneOffsetShape, "an offset of \(id) is not [date, minutes]")
            }
            let day = try self.day(date, "an offset date of \(id)", .zoneOffsetDate)
            if let previous = days.last, day <= previous {
                throw PublishedTimetable.FormatError(.zoneOffsetOrder, "offset dates of \(id) are not ascending")
            }
            let offset = try int32(pair[1], "an offset of \(id)", .zoneOffsetRange)
            guard (-1440...1440).contains(offset) else {
                throw PublishedTimetable.FormatError(.zoneOffsetRange, "an offset of \(id) is outside -1440 to 1440")
            }
            days.append(day)
            minutes.append(offset)
        }
        guard days[0] <= coverageStart else {
            throw PublishedTimetable.FormatError(.zoneOffsetStart, "the first offset of \(id) is after coverage starts")
        }
        return ZoneOffsets(days: days, minutes: minutes)
    }

    private static func record(_ json: HeaderJSON, ids: Set<[UInt8]>, zoneCount: Int) throws -> LocalityRecord {
        let id = try string(try required(json, "id"), "a locality id", .localityId)
        let group = try string(try required(json, "group"), "group of \(id)", .localityGroup)
        guard !group.isEmpty else {
            throw PublishedTimetable.FormatError(.localityGroup, "group of \(id) is empty")
        }
        let zone = try int32(try required(json, "zone"), "zone of \(id)", .localityZone)
        guard zone >= 0, Int(zone) < zoneCount else {
            throw PublishedTimetable.FormatError(.localityZone, "zone of \(id) is outside 0 to \(zoneCount - 1)")
        }
        guard case .object(let namePairs) = try required(json, "names") else {
            throw PublishedTimetable.FormatError(.localityNames, "names of \(id) is not an object")
        }
        var names = [String: String]()
        for (language, name) in namePairs {
            let text = try string(name, "name \(language) of \(id)", .localityNames)
            if names[language] == nil {
                names[language] = text
            }
        }
        let refJSON = try array(try required(json, "ref"), "ref of \(id)", .localityRefShape)
        guard refJSON.count == 2 else {
            throw PublishedTimetable.FormatError(.localityRefShape, "ref of \(id) is not [lat, lon]")
        }
        let ref = try refJSON.map { try int32($0, "a ref value of \(id)", .localityRefInteger) }
        guard (-90000000...90000000).contains(ref[0]) else {
            throw PublishedTimetable.FormatError(.localityRefRange, "ref latitude of \(id) is outside -90000000 to 90000000")
        }
        guard (-180000000...180000000).contains(ref[1]) else {
            throw PublishedTimetable.FormatError(.localityRefRange, "ref longitude of \(id) is outside -180000000 to 180000000")
        }
        let validFrom = try json["validFrom"].map { try day(try string($0, "validFrom of \(id)", .localityValidityDate), "validFrom of \(id)", .localityValidityDate) }
        let validTo = try json["validTo"].map { try day(try string($0, "validTo of \(id)", .localityValidityDate), "validTo of \(id)", .localityValidityDate) }
        if let validFrom, let validTo, validTo < validFrom {
            throw PublishedTimetable.FormatError(.localityValidityOrder, "validTo of \(id) is before validFrom")
        }
        let successors = try json["successors"].map { try strings($0, "successors of \(id)", .localitySuccessor) } ?? []
        for successor in successors where !ids.contains(Array(successor.utf8)) {
            throw PublishedTimetable.FormatError(.localitySuccessor, "successor \(successor) of \(id) is not in the header")
        }
        let geometry: LocalityGeometry
        switch (json["point"], json["area"]) {
        case (let point?, nil):
            let radius = try int32(try required(try object(point, "point of \(id)", .localityPointRadius), "radiusM"), "radiusM of \(id)", .localityPointRadius)
            guard radius >= 1 else {
                throw PublishedTimetable.FormatError(.localityPointRadius, "radiusM of \(id) is below 1")
            }
            geometry = .point(radiusMm: Int64(radius) * 1000)
        case (nil, let area?):
            let polygons = try strings(try required(try object(area, "area of \(id)", .localityAreaPolygons), "polygons"), "polygons of \(id)", .localityAreaPolygons)
            guard !polygons.isEmpty else {
                throw PublishedTimetable.FormatError(.localityAreaPolygons, "polygons of \(id) is empty")
            }
            let tolerance = try int32(try required(area, "toleranceM"), "toleranceM of \(id)", .localityAreaTolerance)
            guard tolerance >= 0 else {
                throw PublishedTimetable.FormatError(.localityAreaTolerance, "toleranceM of \(id) is negative")
            }
            geometry = .area(rings: try polygons.map { try ring($0, id) }, toleranceMm: Int64(tolerance) * 1000)
        default:
            throw PublishedTimetable.FormatError(.localityGeometry, "\(id) must have exactly one of point and area")
        }
        let locality = Locality(
            id: LocalityId(id),
            group: group,
            names: names,
            referencePoint: Coordinates(latitude: Double(ref[0]) / 1000000, longitude: Double(ref[1]) / 1000000),
            validFrom: validFrom.map(CivilDay.date),
            validTo: validTo.map(CivilDay.date),
            successors: successors.map { LocalityId($0) })
        return LocalityRecord(locality: locality, zone: Int(zone), geometry: geometry)
    }

    private static func ring(_ encoded: String, _ id: String) throws -> [Int64] {
        func polyline(_ detail: String) -> PublishedTimetable.FormatError {
            return PublishedTimetable.FormatError(.localityAreaPolyline, "a polygon of \(id) \(detail)")
        }
        let units = Array(encoded.utf8)
        guard !units.isEmpty else {
            throw polyline("is empty")
        }
        var values = [Int64]()
        var latitude: Int64 = 0
        var longitude: Int64 = 0
        var index = 0
        while index < units.count {
            var result: Int64 = 0
            var shift: Int64 = 0
            var chunk: Int64
            repeat {
                guard index < units.count else {
                    throw polyline("is truncated")
                }
                chunk = Int64(units[index]) - 63
                index += 1
                guard chunk >= 0 && chunk <= 63 else {
                    throw polyline("is not an encoded polyline")
                }
                guard shift < 35 else {
                    throw polyline("has a value of more than seven chunks")
                }
                result |= (chunk & 0x1f) << shift
                shift += 5
            } while chunk >= 0x20
            let delta = (result & 1) == 1 ? ~(result >> 1) : result >> 1
            guard Int32(exactly: delta) != nil else {
                throw polyline("has a value that does not fit in 32 bits")
            }
            if values.count.isMultiple(of: 2) {
                latitude += delta
                values.append(latitude)
            } else {
                longitude += delta
                values.append(longitude)
            }
        }
        guard values.count.isMultiple(of: 2) else {
            throw PublishedTimetable.FormatError(.localityAreaRing, "a ring of \(id) has an odd number of values")
        }
        guard values.count >= 6 else {
            throw PublishedTimetable.FormatError(.localityAreaRing, "a ring of \(id) has fewer than three vertices")
        }
        for index in stride(from: 0, to: values.count, by: 2) where !(-90000000...90000000).contains(values[index]) || !(-180000000...180000000).contains(values[index + 1]) {
            throw PublishedTimetable.FormatError(.localityAreaVertex, "a vertex of \(id) is outside the coordinate range")
        }
        return values
    }
}
