//
//  PublishedTimetable.swift
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

private let lf = UInt8(ascii: "\n")
private let cr = UInt8(ascii: "\r")
private let space = UInt8(ascii: " ")
private let magicLine = Array("OTT 1".utf8)
private let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

/// A timetable decoded from `OTT 1` bytes.
///
/// `init(data:)` reads the header and indexes the row lines. A line's cells
/// are decoded on first use, and the decoded minutes or the `FormatError` are
/// kept, so no line is decoded twice.
public final class PublishedTimetable: OfficialTimetableSource, @unchecked Sendable {
    /// The error for bytes that break a rule of the format. `message` starts
    /// with the rule's id, `rule.rawValue`.
    public struct FormatError: Error, Equatable, CustomStringConvertible {
        public let rule: PublishedRule
        public let message: String

        init(_ rule: PublishedRule, _ detail: String) {
            self.rule = rule
            self.message = "\(rule.rawValue): \(detail)"
        }

        public var description: String {
            return message
        }
    }

    private struct RowLine {
        let index: Int
        let locality: Int
        let firstDay: Int64
        let cellsStart: Int
        let cellsEnd: Int
    }

    private enum LineState {
        case pending
        case decoded([UInt16])
        case malformed(FormatError)
    }

    private let data: Data
    private let header: PublishedHeader
    private let lines: [[RowLine]]
    private let lock = NSLock()
    private var states: [LineState]

    /// Throws `FormatError` unless line 1 and the header are valid `OTT 1` and
    /// every row line names a known locality, starts on a date inside coverage
    /// and opens with a full first day of digits.
    public init(data: Data) throws {
        self.data = data
        let (header, lines) = try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) throws -> (PublishedHeader, [[RowLine]]) in
            guard let last = bytes.last else {
                throw FormatError(.fileEmpty, "the file is empty")
            }
            guard last == lf else {
                throw FormatError(.fileLastLineNoLF, "the last line has no LF")
            }
            guard !bytes.contains(cr) else {
                throw FormatError(.fileCR, "the file contains a CR")
            }
            guard !PublishedTimetable.containsByteOrderMark(bytes) else {
                throw FormatError(.fileBOM, "the file contains a byte order mark")
            }
            let firstBreak = bytes.firstIndex(of: lf)!
            guard bytes[..<firstBreak].elementsEqual(magicLine) else {
                throw FormatError(.fileMagic, "line 1 is not \"OTT 1\"")
            }
            guard let secondBreak = bytes[(firstBreak + 1)...].firstIndex(of: lf) else {
                throw FormatError(.fileHeaderAbsent, "the header line is absent")
            }
            let header = try PublishedHeader.parse(Data(bytes[(firstBreak + 1)..<secondBreak]))
            return (header, try PublishedTimetable.indexLines(bytes, from: secondBreak + 1, header: header))
        }
        self.header = header
        self.lines = lines
        self.states = Array(repeating: .pending, count: lines.reduce(0) { $0 + $1.count })
    }

    /// Decodes every line once and throws `FormatError` unless every minute is
    /// 0 to 2879, the core columns strictly increase on every day, no line
    /// crosses 1 January or leaves coverage, and no two lines of one locality
    /// share a day.
    public func validateAllRows() throws {
        for localityLines in lines {
            var previousEnd: Int64? = nil
            for line in localityLines {
                let dayCount = Int64(try days(of: line).count / header.columns.count)
                if let previousEnd, previousEnd > line.firstDay {
                    throw FormatError(.rowOverlap, "two lines of \(id(of: line)) share \(CivilDay.iso(line.firstDay))")
                }
                previousEnd = line.firstDay + dayCount
            }
        }
    }

    /// The first and last covered date.
    public var coverage: (from: DateComponents, to: DateComponents) {
        return header.coverage
    }

    /// The columns of every row, in wire order.
    public var columns: [PublishedColumn] {
        return header.columns
    }

    /// The shadow factor of the published Asr: 1 or 2.
    public var asrShadow: Int {
        return header.asrShadow
    }

    public var authority: String {
        return header.authority
    }

    public var revision: String {
        return String(header.revision)
    }

    public var localities: [Locality] {
        return header.localities.map { $0.locality }
    }

    public func locality(_ id: LocalityId) -> Locality? {
        return record(id)?.locality
    }

    public func localityAt(_ coordinates: Coordinates, on date: DateComponents) throws -> Locality? {
        let day = try OfficialLookupError.day(of: date)
        try OfficialLookupError.check(coordinates)
        return LocalityIndex.resolve(header.localities, at: coordinates, on: day)?.locality
    }

    public func lookup(_ coordinates: Coordinates, on date: DateComponents, localityId: LocalityId?) throws -> OfficialLookup {
        let day = try OfficialLookupError.day(of: date)
        let record: LocalityRecord?
        if let localityId {
            record = self.record(localityId)
        } else {
            try OfficialLookupError.check(coordinates)
            record = LocalityIndex.resolve(header.localities, at: coordinates, on: day)
        }
        guard let record else {
            return .noLocality
        }
        let locality = record.locality
        guard let line = lineStarting(atOrBefore: day, in: lines[header.localityIndex[Array(locality.id.rawValue.utf8)]!]) else {
            return .noRow(locality)
        }
        let minutes = try days(of: line)
        let columnCount = header.columns.count
        let cellOffset = (day - line.firstDay) * Int64(columnCount)
        guard cellOffset + Int64(columnCount) <= Int64(minutes.count) else {
            return .noRow(locality)
        }
        let offset = Int(truncatingIfNeeded: cellOffset)
        return .published(OfficialRow(
            locality: locality,
            dayNumber: day,
            authority: authority,
            revision: revision,
            asrShadow: asrShadow,
            columns: columns,
            minutes: Array(minutes[offset..<(offset + columnCount)]),
            offsetMinutes: header.zones[record.zone].offset(on: day),
            provenance: .published))
    }

    private func record(_ id: LocalityId) -> LocalityRecord? {
        return header.localityIndex[Array(id.rawValue.utf8)].map { header.localities[$0] }
    }

    private func lineStarting(atOrBefore day: Int64, in lines: [RowLine]) -> RowLine? {
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].firstDay <= day {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low == 0 ? nil : lines[low - 1]
    }

    private func days(of line: RowLine) throws -> [UInt16] {
        lock.lock()
        defer { lock.unlock() }
        switch states[line.index] {
        case .decoded(let minutes):
            return minutes
        case .malformed(let error):
            throw error
        case .pending:
            break
        }
        do {
            let minutes = try decode(line)
            states[line.index] = .decoded(minutes)
            return minutes
        } catch let error as FormatError {
            states[line.index] = .malformed(error)
            throw error
        }
    }

    private func decode(_ line: RowLine) throws -> [UInt16] {
        let columnCount = header.columns.count
        let minutes: [UInt16]
        do {
            minutes = try data.withUnsafeBytes { bytes in
                try DeltaCellsCodec.decode(bytes[line.cellsStart..<line.cellsEnd], columns: columnCount)
            }
        } catch let failure as DeltaCellsCodec.Failure {
            throw FormatError(failure.rule, "\(failure.detail) in \(label(of: line))")
        }
        for dayStart in stride(from: 0, to: minutes.count, by: columnCount) {
            for index in 1..<header.coreIndices.count where minutes[dayStart + header.coreIndices[index]] <= minutes[dayStart + header.coreIndices[index - 1]] {
                throw FormatError(.rowCoreOrder, "core columns are not increasing in \(label(of: line))")
            }
        }
        let lastDay = line.firstDay + Int64(minutes.count / columnCount) - 1
        guard CivilDay.year(ofDay: lastDay) == CivilDay.year(ofDay: line.firstDay) else {
            throw FormatError(.rowCrossesYear, "\(label(of: line)) crosses 1 January")
        }
        guard lastDay <= header.lastDay else {
            throw FormatError(.rowEndsAfterCoverage, "\(label(of: line)) ends after coverage")
        }
        return minutes
    }

    private func id(of line: RowLine) -> String {
        return header.localities[line.locality].locality.id.rawValue
    }

    private func label(of line: RowLine) -> String {
        return "the row of \(id(of: line)) starting \(CivilDay.iso(line.firstDay))"
    }

    private static func containsByteOrderMark(_ bytes: UnsafeRawBufferPointer) -> Bool {
        guard bytes.count >= byteOrderMark.count else {
            return false
        }
        return (0...(bytes.count - byteOrderMark.count)).contains { start in
            bytes[start] == byteOrderMark[0] && bytes[start + 1] == byteOrderMark[1] && bytes[start + 2] == byteOrderMark[2]
        }
    }

    private static func indexLines(_ bytes: UnsafeRawBufferPointer, from start: Int, header: PublishedHeader) throws -> [[RowLine]] {
        var lines = header.localities.map { _ in [RowLine]() }
        let digitCount = header.columns.count * 4
        var position = start
        var index = 0
        while position < bytes.count {
            let end = bytes[position...].firstIndex(of: lf)!
            let line = bytes[position..<end]
            guard let firstSpace = line.firstIndex(of: space), let secondSpace = line[(firstSpace + 1)...].firstIndex(of: space) else {
                throw FormatError(.rowFields, "a row line does not have three fields")
            }
            guard !line[(secondSpace + 1)...].contains(space) else {
                throw FormatError(.rowFields, "a row line has more than three fields")
            }
            func id() -> String {
                return String(decoding: line[..<firstSpace], as: UTF8.self)
            }
            guard let locality = header.localityIndex[Array(line[..<firstSpace])] else {
                throw FormatError(.rowLocality, "row locality \(id()) is not in the header")
            }
            guard let firstDay = CivilDay.parse(line[(firstSpace + 1)..<secondSpace]) else {
                throw FormatError(.rowDate, "the first date of a row of \(id()) is not a YYYY-MM-DD calendar day")
            }
            guard firstDay >= header.firstDay, firstDay <= header.lastDay else {
                throw FormatError(.rowCoverage, "a row of \(id()) starts outside coverage")
            }
            let cellsStart = secondSpace + 1
            guard end - cellsStart >= digitCount else {
                throw FormatError(.rowFirstDayLength, "the first day of a row of \(id()) has fewer than \(digitCount) digits")
            }
            guard line[cellsStart..<(cellsStart + digitCount)].allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else {
                throw FormatError(.rowFirstDayDigits, "the first day of a row of \(id()) is not digits")
            }
            lines[locality].append(RowLine(index: index, locality: locality, firstDay: firstDay, cellsStart: cellsStart, cellsEnd: end))
            index += 1
            position = end + 1
        }
        for locality in lines.indices {
            lines[locality].sort { $0.firstDay < $1.firstDay }
        }
        return lines
    }
}
