//
//  MalaysiaZoneMap.swift
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

struct MalaysiaZoneRecord {
    static let alwaysInForceFrom: Int64 = 0
    static let alwaysInForceTo: Int64 = 99999999

    let code: String
    let state: String
    let areas: String
    let validFromDay: Int64
    let validToDay: Int64
    let successors: [String]
    let referenceLatitude: Double
    let referenceLongitude: Double

    func inForce(_ day: Int64) -> Bool {
        return day >= validFromDay && day <= validToDay
    }
}

struct MalaysiaSpecialArea {
    let zone: String
    let name: String
    let latitude: Double
    let longitude: Double
    let radiusMetres: Int
    let region: Int
}

struct MalaysiaZoneMap {
    static let boundaryToleranceMetres = 500
    static let empty = MalaysiaZoneMap(zones: [], specialAreas: [], regions: [])

    let zones: [MalaysiaZoneRecord]
    let specialAreas: [MalaysiaSpecialArea]
    private let regions: [Region]
    private let zonesByCode: [String: MalaysiaZoneRecord]

    private init(zones: [MalaysiaZoneRecord], specialAreas: [MalaysiaSpecialArea], regions: [Region]) {
        self.zones = zones
        self.specialAreas = specialAreas
        self.regions = regions
        var byCode = [String: MalaysiaZoneRecord]()
        for zone in zones {
            byCode[zone.code] = zone
        }
        self.zonesByCode = byCode
    }

    static func parse(_ text: [UInt8]) -> MalaysiaZoneMap? {
        var zones = [MalaysiaZoneRecord]()
        var specialAreas = [MalaysiaSpecialArea]()
        var arcs = [[Int64]]()
        var regions = [Region]()
        for line in text.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            let fields = line.split(separator: UInt8(ascii: "\t"), omittingEmptySubsequences: false)
            func string(_ index: Int) -> String {
                return String(decoding: fields[index], as: UTF8.self)
            }
            switch fields[0].first {
            case UInt8(ascii: "Z"):
                guard fields.count >= 9,
                    let validFrom = day(fromISO: string(4), whenEmpty: MalaysiaZoneRecord.alwaysInForceFrom),
                    let validTo = day(fromISO: string(5), whenEmpty: MalaysiaZoneRecord.alwaysInForceTo),
                    let latitude = Double(string(7)),
                    let longitude = Double(string(8)) else {
                    return nil
                }
                zones.append(MalaysiaZoneRecord(
                    code: string(1),
                    state: string(2),
                    areas: string(3),
                    validFromDay: validFrom,
                    validToDay: validTo,
                    successors: fields[6].isEmpty ? [] : string(6).split(separator: " ").map(String.init),
                    referenceLatitude: latitude,
                    referenceLongitude: longitude))
            case UInt8(ascii: "S"):
                guard fields.count >= 7,
                    let latitude = Double(string(3)),
                    let longitude = Double(string(4)),
                    let radius = Int(string(5)),
                    let region = Int(string(6)) else {
                    return nil
                }
                specialAreas.append(MalaysiaSpecialArea(
                    zone: string(1), name: string(2), latitude: latitude, longitude: longitude, radiusMetres: radius, region: region))
            case UInt8(ascii: "A"):
                guard fields.count >= 2 else {
                    return nil
                }
                arcs.append(decodePolyline(fields[1]))
            case UInt8(ascii: "R"):
                guard fields.count >= 3 else {
                    return nil
                }
                var regionArcs = [[Int64]]()
                for index in string(1).split(separator: " ") {
                    guard let arc = Int(index), arc >= 0, arc < arcs.count else {
                        return nil
                    }
                    regionArcs.append(arcs[arc])
                }
                var rows = [ZoneRow]()
                for row in string(2).split(separator: " ") {
                    guard let parsed = ZoneRow.parse(String(row)) else {
                        return nil
                    }
                    rows.append(parsed)
                }
                regions.append(Region(arcs: regionArcs, rows: rows))
            default:
                return nil
            }
        }
        return MalaysiaZoneMap(zones: zones, specialAreas: specialAreas, regions: regions)
    }

    func zone(_ code: String) -> MalaysiaZoneRecord? {
        return zonesByCode[code]
    }

    func zoneAt(latitude: Double, longitude: Double, day: Int64) -> String? {
        guard let region = regionIndexAt(latitude: latitude, longitude: longitude) else {
            return nil
        }
        for area in specialAreas {
            if area.region == region,
                let zone = zonesByCode[area.zone],
                zone.inForce(day),
                MalaysiaZoneMap.distanceMetres(latitude, longitude, area.latitude, area.longitude) <= Double(area.radiusMetres) {
                return zone.code
            }
        }
        for row in regions[region].rows {
            if let zone = zonesByCode[row.zone], zone.inForce(day), row.matches(latitude: latitude, longitude: longitude) {
                return zone.code
            }
        }
        return nil
    }

    private func regionIndexAt(latitude: Double, longitude: Double) -> Int? {
        let lat = MalaysiaZoneMap.quantize(latitude)
        let lon = MalaysiaZoneMap.quantize(longitude)
        for (index, region) in regions.enumerated() where region.contains(lat: lat, lon: lon) {
            return index
        }
        var nearest: Int? = nil
        var nearestMetres = Double(MalaysiaZoneMap.boundaryToleranceMetres)
        for (index, region) in regions.enumerated() where region.nearBounds(lat: lat, lon: lon, metres: nearestMetres) {
            let metres = region.distanceMetres(lat: lat, lon: lon)
            if metres <= nearestMetres {
                nearest = index
                nearestMetres = metres
            }
        }
        return nearest
    }

    static func quantize(_ degrees: Double) -> Int64 {
        return Int64((degrees * 100000).rounded())
    }

    private static func day(fromISO iso: String, whenEmpty: Int64) -> Int64? {
        if iso.isEmpty {
            return whenEmpty
        }
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let year = Int64(parts[0]), let month = Int64(parts[1]), let day = Int64(parts[2]) else {
            return nil
        }
        return year * 10000 + month * 100 + day
    }

    static func decodePolyline(_ encoded: ArraySlice<UInt8>) -> [Int64] {
        var values = [Int64]()
        var lat: Int64 = 0
        var lon: Int64 = 0
        var result: Int64 = 0
        var shift = 0
        for unit in encoded {
            let byte = Int64(unit) - 63
            result |= (byte & 0x1f) << shift
            shift += 5
            if byte >= 0x20 {
                continue
            }
            let delta = (result & 1) == 1 ? ~(result >> 1) : result >> 1
            if values.count.isMultiple(of: 2) {
                lat += delta
                values.append(lat)
            } else {
                lon += delta
                values.append(lon)
            }
            result = 0
            shift = 0
        }
        return values
    }

    private static let metresPerDegreeLatitude = 110574.0
    private static let metresPerDegreeLongitudeAtEquator = 111320.0

    static func distanceMetres(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let dy = (lat2 - lat1) * metresPerDegreeLatitude
        let dx = (lon2 - lon1) * metresPerDegreeLongitudeAtEquator * cos((lat1 + lat2) / 2 * Double.pi / 180)
        return sqrt(dx * dx + dy * dy)
    }

    private struct ZoneRow {
        let zone: String
        let rule: [Comparison]

        static func parse(_ text: String) -> ZoneRow? {
            guard let colon = text.firstIndex(of: ":") else {
                return ZoneRow(zone: text, rule: [])
            }
            var rule = [Comparison]()
            for part in text[text.index(after: colon)...].split(separator: "&") {
                guard let comparison = Comparison.parse(String(part)) else {
                    return nil
                }
                rule.append(comparison)
            }
            return ZoneRow(zone: String(text[..<colon]), rule: rule)
        }

        func matches(latitude: Double, longitude: Double) -> Bool {
            return rule.allSatisfy { $0.matches(latitude: latitude, longitude: longitude) }
        }
    }

    private struct Comparison {
        enum Operator: String, CaseIterable {
            case lessOrEqual = "<="
            case greaterOrEqual = ">="
            case less = "<"
            case greater = ">"
        }

        let onLatitude: Bool
        let `operator`: Operator
        let value: Double

        static func parse(_ text: String) -> Comparison? {
            guard text.hasPrefix("lat") || text.hasPrefix("lon") else {
                return nil
            }
            let rest = text.dropFirst(3)
            for candidate in Operator.allCases where rest.hasPrefix(candidate.rawValue) {
                guard let value = Double(rest.dropFirst(candidate.rawValue.count)) else {
                    return nil
                }
                return Comparison(onLatitude: text.hasPrefix("lat"), operator: candidate, value: value)
            }
            return nil
        }

        func matches(latitude: Double, longitude: Double) -> Bool {
            let subject = onLatitude ? latitude : longitude
            switch `operator` {
            case .less:
                return subject < value
            case .lessOrEqual:
                return subject <= value
            case .greater:
                return subject > value
            case .greaterOrEqual:
                return subject >= value
            }
        }
    }

    private struct Region {
        let arcs: [[Int64]]
        let rows: [ZoneRow]
        let minLat: Int64
        let maxLat: Int64
        let minLon: Int64
        let maxLon: Int64

        init(arcs: [[Int64]], rows: [ZoneRow]) {
            self.arcs = arcs
            self.rows = rows
            var minLat = Int64.max
            var maxLat = Int64.min
            var minLon = Int64.max
            var maxLon = Int64.min
            for arc in arcs {
                var i = 0
                while i + 1 < arc.count {
                    minLat = min(minLat, arc[i])
                    maxLat = max(maxLat, arc[i])
                    minLon = min(minLon, arc[i + 1])
                    maxLon = max(maxLon, arc[i + 1])
                    i += 2
                }
            }
            self.minLat = minLat
            self.maxLat = maxLat
            self.minLon = minLon
            self.maxLon = maxLon
        }

        func contains(lat: Int64, lon: Int64) -> Bool {
            if lat < minLat || lat > maxLat || lon < minLon || lon > maxLon {
                return false
            }
            var inside = false
            for arc in arcs {
                var i = 2
                while i + 1 < arc.count {
                    let lat1 = arc[i - 2]
                    let lon1 = arc[i - 1]
                    let lat2 = arc[i]
                    let lon2 = arc[i + 1]
                    i += 2
                    if (lat1 > lat) == (lat2 > lat) {
                        continue
                    }
                    let left = (lon - lon1) * (lat2 - lat1)
                    let right = (lat - lat1) * (lon2 - lon1)
                    if lat2 > lat1 ? left < right : left > right {
                        inside.toggle()
                    }
                }
            }
            return inside
        }

        func nearBounds(lat: Int64, lon: Int64, metres: Double) -> Bool {
            let latMargin = Int64((metres / metresPerDegreeLatitude * 100000).rounded(.up))
            let lonMargin = Int64((metres / (metresPerDegreeLongitudeAtEquator * cos(Double(lat) / 100000 * Double.pi / 180)) * 100000).rounded(.up))
            return lat >= minLat - latMargin && lat <= maxLat + latMargin && lon >= minLon - lonMargin && lon <= maxLon + lonMargin
        }

        func distanceMetres(lat: Int64, lon: Int64) -> Double {
            let lonScale = metresPerDegreeLongitudeAtEquator * cos(Double(lat) / 100000 * Double.pi / 180) / 100000
            let latScale = metresPerDegreeLatitude / 100000
            var best = Double.infinity
            for arc in arcs {
                var i = 2
                while i + 1 < arc.count {
                    let y1 = Double(arc[i - 2] - lat) * latScale
                    let x1 = Double(arc[i - 1] - lon) * lonScale
                    let y2 = Double(arc[i] - lat) * latScale
                    let x2 = Double(arc[i + 1] - lon) * lonScale
                    i += 2
                    let dx = x2 - x1
                    let dy = y2 - y1
                    let lengthSquared = dx * dx + dy * dy
                    var t = lengthSquared == 0 ? 0.0 : -(x1 * dx + y1 * dy) / lengthSquared
                    t = t < 0 ? 0.0 : (t > 1 ? 1.0 : t)
                    let px = x1 + t * dx
                    let py = y1 + t * dy
                    let d = px * px + py * py
                    if d < best {
                        best = d
                    }
                }
            }
            return sqrt(best)
        }
    }
}
