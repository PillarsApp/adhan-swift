//
//  OfficialLookup.swift
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

/// The id of a locality as its authority publishes it.
public struct LocalityId: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        return rawValue
    }
}

/// A column a published row may carry. The raw value is the wire name.
public enum PublishedColumn: String, CaseIterable, Sendable {
    case imsak, fajr, sunrise, dhuha, dhuhr, asr, asrHanafi, maghrib, isha, eid

    /// Whether every timetable carries the column: fajr, sunrise, dhuhr, asr,
    /// maghrib and isha.
    public var isCore: Bool {
        switch self {
        case .fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha:
            return true
        case .imsak, .dhuha, .asrHanafi, .eid:
            return false
        }
    }
}

/// A place an authority publishes times for. Equal to another locality when
/// the ids are equal.
public struct Locality: Hashable, Sendable, CustomStringConvertible {
    public let id: LocalityId

    /// A region key for grouped pickers, such as a national region or a
    /// Malaysian state.
    public let group: String

    /// Names by language code. May be empty.
    public let names: [String: String]

    /// The point of a point locality, or the declared centre of an area. The
    /// Hanafi shift of Asr is computed here.
    public let referencePoint: Coordinates

    /// The first day the locality is in force, or nil when it always has been.
    public let validFrom: DateComponents?

    /// The last day the locality is in force, or nil when it has no end.
    public let validTo: DateComponents?

    /// The localities that replace this one after `validTo`.
    public let successors: [LocalityId]

    /// The name in `languageCode`, else in English, else the id.
    public func name(_ languageCode: String) -> String {
        return names[languageCode] ?? names["en"] ?? id.rawValue
    }

    /// Whether the locality is in force on `date`. False for a date without a
    /// year, month and day, or that is not a calendar day.
    public func inForce(on date: DateComponents) -> Bool {
        guard let day = CivilDay.dayNumber(date) else {
            return false
        }
        return inForce(day: day)
    }

    func inForce(day: Int64) -> Bool {
        if let from = validFrom.flatMap(CivilDay.dayNumber), day < from {
            return false
        }
        if let to = validTo.flatMap(CivilDay.dayNumber), day > to {
            return false
        }
        return true
    }

    public var description: String {
        return "Locality(\(id.rawValue))"
    }

    public static func == (lhs: Locality, rhs: Locality) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// One published day of one locality. Only a source constructs a row, so
/// holding one proves the times came from published data.
public struct OfficialRow: Sendable {
    public let locality: Locality

    /// The day the row was published for: year, month and day.
    public let date: DateComponents

    public let authority: String

    public let revision: String

    /// The shadow factor of the published `asr` column: 1 or 2.
    public let asrShadow: Int

    /// The columns the row carries, in wire order.
    public let columns: [PublishedColumn]

    enum Provenance {
        case published
        case embeddedMalaysia(MalaysiaZone)
    }

    let minutes: [UInt16]
    let dayNumber: Int64
    let offsetMinutes: Int32
    let provenance: Provenance

    init(locality: Locality, dayNumber: Int64, authority: String, revision: String, asrShadow: Int, columns: [PublishedColumn], minutes: [UInt16], offsetMinutes: Int32, provenance: Provenance) {
        self.locality = locality
        self.date = CivilDay.date(ofDay: dayNumber)
        self.authority = authority
        self.revision = revision
        self.asrShadow = asrShadow
        self.columns = columns
        self.minutes = minutes
        self.dayNumber = dayNumber
        self.offsetMinutes = offsetMinutes
        self.provenance = provenance
    }

    /// Seconds east of UTC the wall times were published in.
    public var utcOffset: TimeInterval {
        return Double(offsetMinutes) * 60
    }

    /// The published instant of `column`, before adjustments and the Hanafi
    /// shift, or nil when the row has no such column.
    public func published(_ column: PublishedColumn) -> Date? {
        return columns.firstIndex(of: column).map(instant)
    }

    func instant(column index: Int) -> Date {
        return Date(timeIntervalSince1970: Double(dayNumber) * 86400 + (Double(minutes[index]) - Double(offsetMinutes)) * 60)
    }
}

/// The outcome of asking a source for one date at one place.
public enum OfficialLookup: Sendable {
    case published(OfficialRow)

    /// No locality covers the coordinates on the date, or a manual id is
    /// unknown.
    case noLocality

    /// The locality is known but has no row for the date.
    case noRow(Locality)
}

/// A lookup argument no source can answer for.
public enum OfficialLookupError: Error, Equatable {
    /// The date lacks a year, month or day, has one outside 32 bits, or is
    /// not a calendar day.
    case invalidDate(DateComponents)

    /// A latitude outside -90 to 90, a longitude outside -180 to 180, or a
    /// non-finite coordinate.
    case invalidCoordinates(Coordinates)

    static func day(of date: DateComponents) throws -> Int64 {
        guard let day = CivilDay.dayNumber(date) else {
            throw OfficialLookupError.invalidDate(date)
        }
        return day
    }

    static func check(_ coordinates: Coordinates) throws {
        guard abs(coordinates.latitude) <= 90, abs(coordinates.longitude) <= 180 else {
            throw OfficialLookupError.invalidCoordinates(coordinates)
        }
    }
}

/// Anything that answers "the published times here, on this date". A `date`
/// that is not a calendar day, or in automatic resolution a coordinate
/// outside its range, is a caller error and throws `OfficialLookupError`.
public protocol OfficialTimetableSource: Sendable {
    var authority: String { get }

    var revision: String { get }

    /// Every locality the source knows, in force or not, in the source's own
    /// order.
    var localities: [Locality] { get }

    /// The locality with `id`, in force or not, or nil for an unknown id.
    func locality(_ id: LocalityId) -> Locality?

    /// The locality in force at `coordinates` on `date`, or nil when none
    /// covers them. Throws `OfficialLookupError` for a date that is not a
    /// calendar day or a coordinate outside its range.
    func localityAt(_ coordinates: Coordinates, on date: DateComponents) throws -> Locality?

    /// The row at `coordinates` on `date`. A `localityId` skips resolution and
    /// never reads the coordinates: an unknown id is `noLocality`, a known id
    /// is used whether or not it is in force on `date`. Throws
    /// `OfficialLookupError` for a date that is not a calendar day, and
    /// without an id for a coordinate outside its range. A published source
    /// throws `PublishedTimetable.FormatError` for a malformed line of a file
    /// that was never validated, and does not decode that line again.
    func lookup(_ coordinates: Coordinates, on date: DateComponents, localityId: LocalityId?) throws -> OfficialLookup
}

extension OfficialTimetableSource {
    /// The row at `coordinates` on `date`, resolving the locality from the
    /// coordinates.
    public func lookup(_ coordinates: Coordinates, on date: DateComponents) throws -> OfficialLookup {
        return try lookup(coordinates, on: date, localityId: nil)
    }
}
