//
//  HeaderJSON.swift
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

indirect enum HeaderJSON {
    case object([(key: String, value: HeaderJSON)])
    case array([HeaderJSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    var typeName: String {
        switch self {
        case .object:
            return "an object"
        case .array:
            return "an array"
        case .string:
            return "a string"
        case .number:
            return "a number"
        case .bool:
            return "a boolean"
        case .null:
            return "null"
        }
    }

    subscript(key: String) -> HeaderJSON? {
        guard case .object(let pairs) = self else {
            return nil
        }
        return pairs.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
    }

    static func parse(_ bytes: [UInt8]) throws -> HeaderJSON {
        guard String(decoding: bytes, as: UTF8.self).utf8.elementsEqual(bytes) else {
            throw PublishedTimetable.FormatError(.headerJSON, "line 2 is not UTF-8")
        }
        var reader = Reader(bytes: bytes)
        reader.skipSpace()
        guard reader.peek == UInt8(ascii: "{") else {
            throw PublishedTimetable.FormatError(.headerJSON, "line 2 is not a JSON object")
        }
        let value = try reader.value(depth: 1)
        reader.skipSpace()
        guard reader.position == bytes.count else {
            throw PublishedTimetable.FormatError(.headerJSON, "line 2 has bytes after the JSON object")
        }
        if let fault = reader.structureFault ?? reader.valueFault {
            throw fault
        }
        return value
    }

    private struct Reader {
        static let maxDepth = 32

        let bytes: [UInt8]
        var position = 0
        var structureFault: PublishedTimetable.FormatError?
        var valueFault: PublishedTimetable.FormatError?

        var peek: UInt8? {
            return position < bytes.count ? bytes[position] : nil
        }

        mutating func skipSpace() {
            while let byte = peek, byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") {
                position += 1
            }
        }

        func malformed(_ detail: String) -> PublishedTimetable.FormatError {
            return PublishedTimetable.FormatError(.headerJSON, "line 2 is not valid JSON: \(detail) at byte \(position)")
        }

        mutating func expect(_ literal: String) throws {
            for expected in literal.utf8 {
                guard peek == expected else {
                    throw malformed("expected \(literal)")
                }
                position += 1
            }
        }

        mutating func value(depth: Int) throws -> HeaderJSON {
            guard let byte = peek else {
                throw malformed("the line ends inside a value")
            }
            switch byte {
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                guard depth <= Reader.maxDepth else {
                    structureFault = structureFault ?? malformed("nesting is deeper than \(Reader.maxDepth)")
                    try skipNesting()
                    return .null
                }
                return byte == UInt8(ascii: "{") ? try object(depth: depth) : try array(depth: depth)
            case UInt8(ascii: "\""):
                return .string(String(decoding: try string(), as: UTF8.self))
            case UInt8(ascii: "t"):
                try expect("true")
                return .bool(true)
            case UInt8(ascii: "f"):
                try expect("false")
                return .bool(false)
            case UInt8(ascii: "n"):
                try expect("null")
                return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                return .number(try number())
            default:
                throw malformed("unexpected byte \(byte)")
            }
        }

        mutating func skipNesting() throws {
            var closers = [UInt8]()
            while true {
                if peek == UInt8(ascii: "{") || peek == UInt8(ascii: "[") {
                    let closer = peek == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
                    closers.append(closer)
                    position += 1
                    skipSpace()
                    if peek != closer {
                        try skipKey(inside: closer)
                        continue
                    }
                } else {
                    _ = try value(depth: Reader.maxDepth)
                    skipSpace()
                }
                while let closer = closers.last, peek == closer {
                    closers.removeLast()
                    position += 1
                    skipSpace()
                }
                guard let closer = closers.last else {
                    return
                }
                guard peek == UInt8(ascii: ",") else {
                    throw malformed("expected , or \(Character(UnicodeScalar(closer)))")
                }
                position += 1
                skipSpace()
                try skipKey(inside: closer)
            }
        }

        mutating func skipKey(inside closer: UInt8) throws {
            guard closer == UInt8(ascii: "}") else {
                return
            }
            guard peek == UInt8(ascii: "\"") else {
                throw malformed("expected a key")
            }
            _ = try string()
            skipSpace()
            try expect(":")
            skipSpace()
        }

        mutating func object(depth: Int) throws -> HeaderJSON {
            position += 1
            var pairs = [(key: String, value: HeaderJSON)]()
            var keys = Set<[UInt8]>()
            skipSpace()
            if peek == UInt8(ascii: "}") {
                position += 1
                return .object(pairs)
            }
            while true {
                skipSpace()
                guard peek == UInt8(ascii: "\"") else {
                    throw malformed("expected a key")
                }
                let key = try string()
                let text = String(decoding: key, as: UTF8.self)
                if !keys.insert(key).inserted, structureFault == nil {
                    structureFault = PublishedTimetable.FormatError(.headerDuplicateKey, "key \(text) appears twice in one object")
                }
                skipSpace()
                try expect(":")
                skipSpace()
                pairs.append((key: text, value: try value(depth: depth + 1)))
                skipSpace()
                switch peek {
                case UInt8(ascii: ","):
                    position += 1
                case UInt8(ascii: "}"):
                    position += 1
                    return .object(pairs)
                default:
                    throw malformed("expected , or }")
                }
            }
        }

        mutating func array(depth: Int) throws -> HeaderJSON {
            position += 1
            var values = [HeaderJSON]()
            skipSpace()
            if peek == UInt8(ascii: "]") {
                position += 1
                return .array(values)
            }
            while true {
                skipSpace()
                values.append(try value(depth: depth + 1))
                skipSpace()
                switch peek {
                case UInt8(ascii: ","):
                    position += 1
                case UInt8(ascii: "]"):
                    position += 1
                    return .array(values)
                default:
                    throw malformed("expected , or ]")
                }
            }
        }

        mutating func string() throws -> [UInt8] {
            position += 1
            var utf8 = [UInt8]()
            while true {
                guard let byte = peek else {
                    throw malformed("the line ends inside a string")
                }
                position += 1
                switch byte {
                case UInt8(ascii: "\""):
                    return utf8
                case UInt8(ascii: "\\"):
                    try escape(into: &utf8)
                case 0..<0x20:
                    throw malformed("a control character is not escaped")
                default:
                    utf8.append(byte)
                }
            }
        }

        mutating func escape(into utf8: inout [UInt8]) throws {
            guard let byte = peek else {
                throw malformed("the line ends inside an escape")
            }
            position += 1
            switch byte {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"):
                utf8.append(byte)
            case UInt8(ascii: "b"):
                utf8.append(0x08)
            case UInt8(ascii: "f"):
                utf8.append(0x0C)
            case UInt8(ascii: "n"):
                utf8.append(0x0A)
            case UInt8(ascii: "r"):
                utf8.append(0x0D)
            case UInt8(ascii: "t"):
                utf8.append(0x09)
            case UInt8(ascii: "u"):
                let unit = try hex4()
                var scalarValue = UInt32(unit)
                if (0xD800...0xDBFF).contains(unit), let low = lowSurrogateEscape() {
                    scalarValue = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
                }
                if let scalar = UnicodeScalar(scalarValue) {
                    utf8.append(contentsOf: Array(String(scalar).utf8))
                } else {
                    valueFault = valueFault ?? malformed("a surrogate escape has no partner")
                    utf8.append(contentsOf: Reader.distinctBytes(ofLoneSurrogate: unit))
                }
            default:
                throw malformed("\\\(Character(UnicodeScalar(byte))) is not an escape")
            }
        }

        mutating func lowSurrogateEscape() -> UInt16? {
            let start = position
            if bytes[position...].starts(with: "\\u".utf8) {
                position += 2
                if let low = try? hex4(), (0xDC00...0xDFFF).contains(low) {
                    return low
                }
            }
            position = start
            return nil
        }

        static func distinctBytes(ofLoneSurrogate unit: UInt16) -> [UInt8] {
            return [0xED, 0x80 | UInt8(unit >> 6 & 0x3F), 0x80 | UInt8(unit & 0x3F)]
        }

        mutating func hex4() throws -> UInt16 {
            var value: UInt16 = 0
            for _ in 0..<4 {
                guard let byte = peek, let digit = Reader.hexDigit(byte) else {
                    throw malformed("\\u needs four hex digits")
                }
                position += 1
                value = value << 4 | UInt16(digit)
            }
            return value
        }

        static func hexDigit(_ byte: UInt8) -> UInt8? {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                return byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"):
                return byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"):
                return byte - UInt8(ascii: "A") + 10
            default:
                return nil
            }
        }

        mutating func number() throws -> String {
            let start = position
            if peek == UInt8(ascii: "-") {
                position += 1
            }
            if peek == UInt8(ascii: "0") {
                position += 1
            } else {
                try digits()
            }
            if peek == UInt8(ascii: ".") {
                position += 1
                try digits()
            }
            if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
                position += 1
                if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") {
                    position += 1
                }
                try digits()
            }
            let text = String(decoding: bytes[start..<position], as: UTF8.self)
            if Double(text)?.isFinite != true {
                valueFault = valueFault ?? malformed("\(text) is not a finite number")
            }
            return text
        }

        mutating func digits() throws {
            guard let byte = peek, byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
                throw malformed("expected a digit")
            }
            while let byte = peek, byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
                position += 1
            }
        }
    }
}
