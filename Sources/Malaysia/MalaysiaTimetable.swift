//
//  MalaysiaTimetable.swift
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

enum MalaysiaResources {
    static func bytes(_ name: String) -> [UInt8]? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt"),
            let data = try? Data(contentsOf: url) else {
            return nil
        }
        return [UInt8](data)
    }
}

/// The lines of malaysia_times.txt, indexed by `<zone> <year>` and decoded
/// on first use. The decode cache is the only mutable state; NSLock keeps the
/// synchronous lookup usable below the deployment targets of Mutex.
final class MalaysiaTimesLookup: @unchecked Sendable {
    static let shared = MalaysiaTimesLookup(bytes: MalaysiaResources.bytes("malaysia_times") ?? [])

    let bytes: [UInt8]
    private let lines: [String: Range<Int>]
    private let lock = NSLock()
    private var decoded = [String: [UInt16]]()

    init(bytes: [UInt8]) {
        self.bytes = bytes
        var lines = [String: Range<Int>]()
        for range in MalaysiaTimesCodec.lineRanges(bytes) {
            if let header = MalaysiaTimesCodec.header(bytes[range]) {
                lines[header] = range
            }
        }
        self.lines = lines
    }

    func row(zone: String, year: Int, dayIndex: Int) -> ArraySlice<UInt16>? {
        let key = "\(zone) \(year)"
        guard let range = lines[key] else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        if let minutes = decoded[key] {
            return MalaysiaZoneYear(zone: zone, year: year, minutes: minutes).day(dayIndex)
        }
        guard let zoneYear = MalaysiaTimesCodec.decodeLine(bytes[range]) else {
            return nil
        }
        decoded[key] = zoneYear.minutes
        return zoneYear.day(dayIndex)
    }
}
