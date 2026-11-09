//
//  LocalityIndex.swift
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

enum LocalityGeometry {
    case point(radiusMm: Int64)
    case area(rings: [[Int64]], toleranceMm: Int64)
}

struct LocalityRecord {
    let locality: Locality
    let zone: Int
    let geometry: LocalityGeometry
}

enum LocalityIndex {
    private static let earthRadiusMetres = 6371008.8
    private static let metresPerDegreeLatitude = 110574.0
    private static let metresPerDegreeLongitudeAtEquator = 111320.0

    static func resolve(_ records: [LocalityRecord], at coordinates: Coordinates, on day: Int64) -> LocalityRecord? {
        let latitude = coordinates.latitude
        let longitude = coordinates.longitude
        var nearest: LocalityRecord? = nil
        var nearestMm: Int64 = 0
        for record in records {
            guard case .point(let radiusMm) = record.geometry, record.locality.inForce(day: day) else {
                continue
            }
            let reference = record.locality.referencePoint
            let mm = haversineMm(latitude, longitude, reference.latitude, reference.longitude)
            if mm > radiusMm {
                continue
            }
            if let current = nearest, mm > nearestMm || (mm == nearestMm && !record.locality.id.rawValue.utf8.lexicographicallyPrecedes(current.locality.id.rawValue.utf8)) {
                continue
            }
            nearest = record
            nearestMm = mm
        }
        if let nearest {
            return nearest
        }
        let quantizedLatitude = Int64((latitude * 1000000).rounded())
        let quantizedLongitude = Int64((longitude * 1000000).rounded())
        for record in records {
            guard case .area(let rings, let toleranceMm) = record.geometry, record.locality.inForce(day: day) else {
                continue
            }
            if contains(rings, lat: quantizedLatitude, lon: quantizedLongitude) || edgeDistanceMm(latitude, longitude, rings) <= toleranceMm {
                return record
            }
        }
        return nil
    }

    static func haversineMm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Int64 {
        let phi1 = radians(lat1)
        let phi2 = radians(lat2)
        let dPhi = radians(lat2 - lat1)
        let dLambda = radians(lon2 - lon1)
        let a = min(max(pow(sin(dPhi / 2), 2) + cos(phi1) * cos(phi2) * pow(sin(dLambda / 2), 2), 0), 1)
        let d = 2 * earthRadiusMetres * atan2(sqrt(a), sqrt(1 - a))
        return Int64((d * 1000).rounded())
    }

    static func contains(_ rings: [[Int64]], lat: Int64, lon: Int64) -> Bool {
        var inside = false
        for ring in rings {
            let vertices = ring.count / 2
            for i in 0..<vertices {
                let j = (i + 1) % vertices
                let lat1 = ring[2 * i]
                let lon1 = ring[2 * i + 1]
                let lat2 = ring[2 * j]
                let lon2 = ring[2 * j + 1]
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

    static func edgeDistanceMm(_ lat0: Double, _ lon0: Double, _ rings: [[Int64]]) -> Int64 {
        let perDegreeLongitude = metresPerDegreeLongitudeAtEquator * cos(radians(lat0))
        var best = Double.infinity
        for ring in rings {
            let vertices = ring.count / 2
            for i in 0..<vertices {
                let j = (i + 1) % vertices
                let y1 = (Double(ring[2 * i]) / 1e6 - lat0) * metresPerDegreeLatitude
                let x1 = (Double(ring[2 * i + 1]) / 1e6 - lon0) * perDegreeLongitude
                let y2 = (Double(ring[2 * j]) / 1e6 - lat0) * metresPerDegreeLatitude
                let x2 = (Double(ring[2 * j + 1]) / 1e6 - lon0) * perDegreeLongitude
                let dx = x2 - x1
                let dy = y2 - y1
                let lengthSquared = dx * dx + dy * dy
                var t = lengthSquared == 0 ? 0.0 : -(x1 * dx + y1 * dy) / lengthSquared
                t = min(max(t, 0), 1)
                let px = x1 + t * dx
                let py = y1 + t * dy
                best = min(best, sqrt(px * px + py * py))
            }
        }
        return Int64(exactly: (best * 1000).rounded()) ?? Int64.max
    }

    private static func radians(_ degrees: Double) -> Double {
        return degrees * Double.pi / 180
    }
}
