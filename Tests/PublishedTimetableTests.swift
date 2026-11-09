import XCTest
@testable import Adhan

final class PublishedTimetableTests: XCTestCase {
    private let january1 = DateComponents(year: 2026, month: 1, day: 1)
    private let good = Coordinates(latitude: 10, longitude: 10)
    private let bad = Coordinates(latitude: 20, longitude: 20)
    private let goodLine = "good 2026-01-01 030006301220164018201950dddddd\n"

    private func header(
        fields: String = "\"authority\":\"xx\",\"revision\":1,\"part\":\"all\"",
        zones: String = "{\"id\":\"Etc/UTC\",\"offsets\":[[\"2026-01-01\",0]]}",
        goodNames: String = "{}",
        goodGeometry: String = "\"point\":{\"radiusM\":1000}"
    ) -> String {
        return "OTT 1\n{\(fields),\"coverage\":[\"2026-01-01\",\"2026-12-31\"],\"columns\":[\"fajr\",\"sunrise\",\"dhuhr\",\"asr\",\"maghrib\",\"isha\"],\"asrShadow\":1,\"zones\":[\(zones)],\"localities\":[{\"id\":\"good\",\"group\":\"g\",\"zone\":0,\"names\":\(goodNames),\"ref\":[10000000,10000000],\(goodGeometry)},{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000}}]}\n"
    }

    private func assertRule(_ file: String, _ rule: PublishedRule, file sourceFile: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try PublishedTimetable(data: Data(file.utf8)), rule.rawValue, file: sourceFile, line: line) { error in
            XCTAssertEqual((error as? PublishedTimetable.FormatError)?.rule, rule, "\(error)", file: sourceFile, line: line)
        }
    }

    private func assertHeaderRule(_ header: String, _ rule: PublishedRule, file: StaticString = #filePath, line: UInt = #line) {
        assertRule(header + goodLine, rule, file: file, line: line)
    }

    private func area(_ polyline: String) -> String {
        return "\"area\":{\"polygons\":[\"\(polyline)\"],\"toleranceM\":0}"
    }

    private func timetable(_ header: String, _ rows: String) throws -> PublishedTimetable {
        return try PublishedTimetable(data: Data((header + rows).utf8))
    }

    private func assertDecodeFails(_ header: String, _ expectedMessagePart: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try timetable(header, goodLine), expectedMessagePart, file: file, line: line) { error in
            let message = (error as? PublishedTimetable.FormatError)?.message ?? "\(error)"
            XCTAssertTrue(message.contains(expectedMessagePart), message, file: file, line: line)
        }
    }

    private func assertBadLineThrowsOnLookup(_ badLine: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let timetable = try self.timetable(header(), goodLine + badLine)
        guard case .published(let row) = try timetable.lookup(good, on: january1) else {
            return XCTFail("the good line gave no row", file: file, line: line)
        }
        XCTAssertEqual(row.published(.fajr), PublishedVectors.instant("2026-01-01T03:00:00Z"), file: file, line: line)
        var fromLookup: PublishedTimetable.FormatError?
        XCTAssertThrowsError(try timetable.lookup(bad, on: january1), badLine, file: file, line: line) { error in
            fromLookup = error as? PublishedTimetable.FormatError
            let message = fromLookup?.message ?? "\(error)"
            XCTAssertTrue(message.contains("bad"), message, file: file, line: line)
            XCTAssertTrue(message.contains("2026-01-01"), message, file: file, line: line)
        }
        XCTAssertThrowsError(try timetable.validateAllRows(), badLine, file: file, line: line) { error in
            XCTAssertEqual(error as? PublishedTimetable.FormatError, fromLookup, file: file, line: line)
        }
    }

    func testABadLineThrowsOnLookup() throws {
        try assertBadLineThrowsOnLookup("bad 2026-01-01 030006301220164018201950ddddz\n")
    }

    func testALineIsDecodedOnceWhetherItFailsOrSucceeds() throws {
        let badLine = "bad 2026-01-01 030006301220164018201950dddddz\n"
        let bytes = Array((header() + goodLine + badLine).utf8)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
        defer { buffer.deallocate() }
        buffer.initialize(from: bytes, count: bytes.count)
        let shared = Data(bytesNoCopy: buffer, count: bytes.count, deallocator: .none)
        let badCell = bytes.count - 2
        XCTAssertEqual(bytes[badCell], UInt8(ascii: "z"))
        let goodCell = (header() + goodLine).utf8.count - 2
        XCTAssertEqual(bytes[goodCell], UInt8(ascii: "d"))
        let timetable = try PublishedTimetable(data: shared)
        var first: PublishedTimetable.FormatError?
        XCTAssertThrowsError(try timetable.lookup(bad, on: january1)) { error in
            first = error as? PublishedTimetable.FormatError
        }
        buffer[badCell] = UInt8(ascii: "d")
        guard case .published = try PublishedTimetable(data: shared).lookup(bad, on: january1) else {
            return XCTFail("the buffer was copied, so the test cannot patch the bytes the timetable reads")
        }
        XCTAssertThrowsError(try timetable.lookup(bad, on: january1)) { error in
            XCTAssertEqual(error as? PublishedTimetable.FormatError, first)
        }
        guard case .published(let row) = try timetable.lookup(good, on: january1) else {
            return XCTFail("the good line gave no row")
        }
        buffer[goodCell] = UInt8(ascii: "z")
        XCTAssertThrowsError(try PublishedTimetable(data: shared).lookup(good, on: january1))
        guard case .published(let again) = try timetable.lookup(good, on: january1) else {
            return XCTFail("the good line gave no row after its bytes were corrupted")
        }
        XCTAssertEqual(again.published(.fajr), row.published(.fajr))
        XCTAssertEqual(again.published(.isha), row.published(.isha))
    }

    func testATildeTakesExactlyFourAsciiDigits() throws {
        for cells in ["~+500", "~-030", "~20+5", "~\u{A0}500", "~05\t0"] {
            try assertBadLineThrowsOnLookup("bad 2026-01-01 030006301220164018201950\(cells)ddddd\n")
        }
        XCTAssertThrowsError(try timetable(header(), goodLine + "bad 2026-01-01 030006301220164018201950~ 500ddddd\n"))
    }

    func testTheFirstDayTakesOnlyAsciiDigits() {
        for digits in ["+300", "0300\u{A0}", " 300", "03.0"] {
            XCTAssertThrowsError(try timetable(header(), goodLine + "bad 2026-01-01 \(digits)06301220164018201950\n"), digits)
        }
    }

    func testADuplicateKeyAnywhereInTheHeaderFailsToDecode() {
        assertDecodeFails(header(fields: "\"authority\":\"xx\",\"revision\":1,\"revision\":2,\"part\":\"all\""), "revision")
        assertDecodeFails(header(goodNames: "{\"en\":\"Good\"},\"names\":{\"en\":\"Better\"}"), "names")
        assertDecodeFails(header(goodNames: "{\"en\":\"Good\",\"en\":\"Better\"}"), "en")
    }

    func testADuplicateZoneIdFailsToDecode() {
        assertDecodeFails(header(zones: "{\"id\":\"Asia/Riyadh\",\"offsets\":[[\"2026-01-01\",180]]},{\"id\":\"Asia/Riyadh\",\"offsets\":[[\"2026-01-01\",180]]}"), "Asia/Riyadh")
    }

    func testHeaderStringsCompareByCodeUnits() throws {
        let nfc = "\u{00E9}"
        let nfd = "e\u{0301}"
        let kelvin = "\u{212A}"
        var names: PublishedTimetable?
        XCTAssertNoThrow(names = try timetable(header(goodNames: "{\"\(nfc)\":\"a\",\"\(nfd)\":\"b\"}"), goodLine))
        XCTAssertEqual(names?.locality(LocalityId("good"))?.names[nfd], "a")
        XCTAssertNoThrow(try timetable(header(goodNames: "{\"\(kelvin)\":\"a\",\"K\":\"b\"}"), goodLine))
        var twoZones: PublishedTimetable?
        XCTAssertNoThrow(twoZones = try timetable(header(zones: "{\"id\":\"Caf\(nfc)\",\"offsets\":[[\"2026-01-01\",0]]},{\"id\":\"Caf\(nfd)\",\"offsets\":[[\"2026-01-01\",60]]}").replacingOccurrences(of: "\"id\":\"good\",\"group\":\"g\",\"zone\":0", with: "\"id\":\"good\",\"group\":\"g\",\"zone\":1"), goodLine))
        if case .published(let row)? = try twoZones?.lookup(good, on: january1) {
            XCTAssertEqual(row.utcOffset, 3600)
        } else {
            XCTFail("the good line on the second zone gave no row")
        }
        assertHeaderRule(locality("{\"id\":\"K1\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000},\"successors\":[\"\(kelvin)1\"]}"), .localitySuccessor)
        assertRule(header().replacingOccurrences(of: "\"id\":\"bad\"", with: "\"id\":\"K1\"") + goodLine + "\(kelvin)1 2026-01-01 030006301220164018201950dddddd\n", .rowLocality)
    }

    func testUnsortedNamesAndANegativeOffsetAreValid() throws {
        let timetable = try self.timetable(header(zones: "{\"id\":\"America/Sao_Paulo\",\"offsets\":[[\"2026-01-01\",-300]]}", goodNames: "{\"pt\":\"Bom\",\"en\":\"Good\",\"ar\":\"جيد\"}"), goodLine)
        let good = try XCTUnwrap(timetable.locality(LocalityId("good")))
        XCTAssertEqual(good.names, ["pt": "Bom", "en": "Good", "ar": "جيد"])
        guard case .published(let row) = try timetable.lookup(self.good, on: january1) else {
            return XCTFail("the good line gave no row")
        }
        XCTAssertEqual(row.utcOffset, -5 * 3600)
        XCTAssertEqual(row.published(.fajr), PublishedVectors.instant("2026-01-01T08:00:00Z"))
    }

    func testHanafiIsNilWhereTheSunReachesNoAsrAngle() throws {
        func polar(columns: String, cells: String) throws -> PublishedTimetable {
            return try PublishedTimetable(data: Data("""
                OTT 1
                {"authority":"xx","revision":1,"part":"all","coverage":["2026-12-21","2026-12-21"],"columns":[\(columns)],"asrShadow":1,"zones":[{"id":"Europe/Oslo","offsets":[["2026-12-21",60]]}],"localities":[{"id":"north","group":"n","zone":0,"names":{},"ref":[69650000,18950000],"point":{"radiusM":1000}}]}
                north 2026-12-21 \(cells)

                """.utf8))
        }
        let tromso = Coordinates(latitude: 69.65, longitude: 18.95)
        let december21 = DateComponents(year: 2026, month: 12, day: 21)
        let sixColumns = try polar(columns: "\"fajr\",\"sunrise\",\"dhuhr\",\"asr\",\"maghrib\",\"isha\"", cells: "060010001200125014001600")
        guard case .published(let row) = try sixColumns.lookup(tromso, on: december21) else {
            return XCTFail("the polar row was not found")
        }
        let shafi = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.shafi)))
        XCTAssertEqual(shafi.asr, PublishedVectors.instant("2026-12-21T11:50:00Z"))
        XCTAssertNil(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.hanafi)))
        let withHanafi = try polar(columns: "\"fajr\",\"sunrise\",\"dhuhr\",\"asr\",\"asrHanafi\",\"maghrib\",\"isha\"", cells: "0600100012001250131014001600")
        guard case .published(let hanafiRow) = try withHanafi.lookup(tromso, on: december21) else {
            return XCTFail("the polar row with asrHanafi was not found")
        }
        let hanafi = try XCTUnwrap(PrayerTimes(official: hanafiRow, parameters: PublishedVectors.parameters(.hanafi)))
        XCTAssertEqual(hanafi.asr, PublishedVectors.instant("2026-12-21T12:10:00Z"))
    }

    func testAHanafiShiftBeyondThirtyTwoBitsGivesNoAsr() throws {
        for (latitude, longitude, month, day) in [(89974000, -125711240, 3, 22), (-89920000, 167376940, 3, 16)] {
            let date = String(format: "2026-%02d-%02d", month, day)
            let nearThePole = try PublishedTimetable(data: Data("""
                OTT 1
                {"authority":"xx","revision":1,"part":"all","coverage":["\(date)","\(date)"],"columns":["fajr","sunrise","dhuhr","asr","maghrib","isha"],"asrShadow":1,"zones":[{"id":"Etc/UTC","offsets":[["\(date)",0]]}],"localities":[{"id":"pole","group":"g","zone":0,"names":{},"ref":[\(latitude),\(longitude)],"point":{"radiusM":1}}]}
                pole \(date) 030004000700080009001000

                """.utf8))
            guard case .published(let row) = try nearThePole.lookup(Coordinates(latitude: Double(latitude) / 1e6, longitude: Double(longitude) / 1e6), on: DateComponents(year: 2026, month: month, day: day)) else {
                return XCTFail("the near-pole row on \(date) was not found")
            }
            let shafi = try XCTUnwrap(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.shafi)), date)
            XCTAssertEqual(shafi.asr, PublishedVectors.instant("\(date)T08:00:00Z"), date)
            XCTAssertNil(PrayerTimes(official: row, parameters: PublishedVectors.parameters(.hanafi)), date)
        }
    }

    private func fields(revision: String) -> String {
        return "\"authority\":\"xx\",\"revision\":\(revision),\"part\":\"all\""
    }

    private func locality(_ body: String) -> String {
        return header().replacingOccurrences(of: "{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000}}", with: body)
    }

    func testANumberThatIsNotA32BitIntegerBreaksTheIntegerRule() {
        for text in ["1.0", "12.0", "1e0", "1e7", "-0.5", "2147483648", "-2147483649", "-9223372036854775808"] {
            assertHeaderRule(header(fields: fields(revision: text)), .headerRevision)
            assertHeaderRule(header().replacingOccurrences(of: "\"asrShadow\":1", with: "\"asrShadow\":\(text)"), .headerAsrShadow)
            assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":\(text),\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000}}"), .localityZone)
            assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[\(text),20000000],\"point\":{\"radiusM\":1000}}"), .localityRefInteger)
            assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":\(text)}}"), .localityPointRadius)
            assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"area\":{\"polygons\":[\"_gjaR_gjaR_c`|@??_c`|@\"],\"toleranceM\":\(text)}}"), .localityAreaTolerance)
            assertHeaderRule(header(zones: "{\"id\":\"Etc/UTC\",\"offsets\":[[\"2026-01-01\",\(text)]]}"), .zoneOffsetRange)
        }
        assertHeaderRule(header(fields: fields(revision: "1e400")), .headerJSON)
        assertHeaderRule(header(fields: fields(revision: "1") + ",\"ignored\":1e400"), .headerJSON)
        XCTAssertNoThrow(try timetable(header(fields: fields(revision: "1") + ",\"ignored\":{\"a\":[1.5,2e3],\"b\":null,\"c\":true,\"d\":\"\\u00e9\"}"), goodLine))
    }

    func testA32BitIntegerOutsideTheFieldBreaksTheRangeRule() {
        assertHeaderRule(header(fields: fields(revision: "-1")), .headerRevision)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":-1,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000}}"), .localityZone)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[90000001,20000000],\"point\":{\"radiusM\":1000}}"), .localityRefRange)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":0}}"), .localityPointRadius)
        assertHeaderRule(header(zones: "{\"id\":\"Etc/UTC\",\"offsets\":[[\"2026-01-01\",1441]]}"), .zoneOffsetRange)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[-2147483648,20000000],\"point\":{\"radiusM\":1000}}"), .localityRefRange)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,-2147483648],\"point\":{\"radiusM\":1000}}"), .localityRefRange)
        assertHeaderRule(header(zones: "{\"id\":\"Etc/UTC\",\"offsets\":[[\"2026-01-01\",-2147483648]]}"), .zoneOffsetRange)
    }

    func testAPresentKeyWithANullValueBreaksItsOwnRule() {
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000},\"area\":null}"), .localityGeometry)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":null}"), .localityPointRadius)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"area\":null}"), .localityAreaPolygons)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000},\"validFrom\":null}"), .localityValidityDate)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000},\"validTo\":null}"), .localityValidityDate)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000},\"successors\":null}"), .localitySuccessor)
    }

    func testALocalityIdIsCheckedOverEveryByte() {
        for id in ["good\\n", "good\\u0000", "goo\\u00e9", "good ", "\\ud83d\\ude00"] {
            assertHeaderRule(locality("{\"id\":\"\(id)\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000}}"), .localityId)
        }
        XCTAssertNoThrow(try timetable(locality("{\"id\":\"a.b_c-D9\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000}}"), goodLine))
    }

    func testAWrongShapeBreaksTheFieldRule() {
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":5}"), .localityPointRadius)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":[],\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000}}"), .localityNames)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{\"ref\":5},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000}}"), .localityNames)
        assertHeaderRule(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[20000000,20000000],\"point\":{\"radiusM\":1000},\"successors\":\"good\"}"), .localitySuccessor)
        for line2 in ["\"abc\"", "[]", "42", "{\"a\":1}x", "{\"a\":\"\\ud800\"}", "{\"a\":\"\\q\"}", "{\"a\":\"\\x41\"}", String(repeating: "[", count: 33) + String(repeating: "]", count: 33), "{\"a\":" + String(repeating: "[", count: 32) + String(repeating: "]", count: 32) + "}"] {
            assertRule("OTT 1\n\(line2)\n" + goodLine, .headerJSON)
        }
        XCTAssertNoThrow(try timetable(header(fields: fields(revision: "1") + ",\"deep\":" + String(repeating: "[", count: 31) + String(repeating: "]", count: 31)), goodLine))
        assertHeaderRule(header(fields: "\"authority\":\"xx\",\"revision\":12,\"revision\":13,\"part\":\"all\""), .headerDuplicateKey)
        assertHeaderRule(header(goodNames: "{\"en\":\"Good\",\"\\u0065n\":\"Better\"}"), .headerDuplicateKey)
    }

    func testASyntaxErrorOutranksARepeatedKeyBeforeIt() {
        let repeated = header(goodNames: "{\"en\":\"a\",\"en\":\"b\"}")
        let openObject = String(repeated.dropLast(2))
        let brokenEndings = [
            ",\"z\" 1}\n",
            ",\"z\":\"\\q\"}\n",
            ",\"z\":01}\n",
            ",\"z\":\"\u{01}\"}\n",
            "}x\n"
        ]
        for ending in brokenEndings {
            assertRule(openObject + ending + goodLine, .headerJSON)
        }
        assertRule(String(header().dropLast(2)) + ",\"z\":{\"a\":1,\"a\":2,}}\n" + goodLine, .headerJSON)
        assertRule(header(goodNames: "{\"en\":\"a\",\"en\":\"b\"},,") + goodLine, .headerJSON)
        assertRule(String(repeated.dropLast(6)) + "\n" + goodLine, .headerJSON)
        var notUTF8 = Data((openObject + ",\"z\":\"").utf8)
        notUTF8.append(0xFF)
        notUTF8.append(Data(("\"}\n" + goodLine).utf8))
        XCTAssertThrowsError(try PublishedTimetable(data: notUTF8)) { error in
            XCTAssertEqual((error as? PublishedTimetable.FormatError)?.rule, .headerJSON, "\(error)")
        }
    }

    func testARepeatedKeyOutranksTheNonSyntaxPartsOfTheJSONRuleAfterIt() {
        let openObject = String(header(goodNames: "{\"en\":\"a\",\"en\":\"b\"}").dropLast(2))
        let endings = [
            ",\"z\":\"\\ud800\"}\n",
            ",\"z\":\"\\ud800\\u0041\"}\n",
            ",\"z\":\"\\udc00\"}\n",
            ",\"z\":1e999}\n",
            ",\"z\":" + String(repeating: "[", count: 32) + String(repeating: "]", count: 32) + "}\n"
        ]
        for ending in endings {
            assertRule(openObject + ending + goodLine, .headerDuplicateKey)
        }
    }

    func testASyntaxFaultAfterARepeatedKeyAndAnotherFaultReportsTheJSONRule() {
        let openObject = String(header(goodNames: "{\"en\":\"a\",\"en\":\"b\"}").dropLast(2))
        let tooDeep = String(repeating: "[", count: 32) + String(repeating: "]", count: 32)
        let endings = [
            ",\"z\":" + String(repeating: "{\"k\":", count: 100_000),
            ",\"z\":" + String(repeating: "[", count: 100_000),
            ",\"z\":" + String(repeating: "[", count: 40),
            ",\"z\":" + tooDeep + "}x",
            ",\"z\":" + tooDeep + ",\"y\" 1}",
            ",\"z\":\"\\udc00\",\"y\" 1}",
            ",\"z\":1e999}x",
            ",\"z\":1e999,\"y\" 1}",
            ",\"z\":1e999,}",
            ",\"z\":1e999",
            ",\"z\":\"\\ud800\\u0041\",\"y\" 1}",
            ",\"z\":\"\\ud800\"}x",
            ",\"z\":\"\\ud800\",\"y\" 1}",
            ",\"z\":\"\\ud800"
        ]
        for ending in endings {
            assertRule(openObject + ending + "\n" + goodLine, .headerJSON)
        }
        var notUTF8 = Data((openObject + ",\"z\":\"\\ud800\",\"y\":\"").utf8)
        notUTF8.append(0xFF)
        notUTF8.append(Data(("\"}\n" + goodLine).utf8))
        XCTAssertThrowsError(try PublishedTimetable(data: notUTF8)) { error in
            XCTAssertEqual((error as? PublishedTimetable.FormatError)?.rule, .headerJSON, "\(error)")
        }
    }

    func testARepeatedKeyOutranksEveryNonSyntaxFaultExceptNestingThatOpensBeforeIt() {
        let plain = String(header().dropLast(2))
        let repeated = ",\"q\":{\"a\":1,\"a\":2}"
        let tooDeep = ",\"z\":" + String(repeating: "[", count: 32) + String(repeating: "]", count: 32)
        for fault in [",\"z\":1e999", ",\"z\":\"\\ud800\"", ",\"z\":\"\\udc00\"", ",\"z\":\"\\ud800\\u0041\""] {
            assertRule(plain + fault + repeated + "}\n" + goodLine, .headerDuplicateKey)
            assertRule(plain + repeated + fault + "}\n" + goodLine, .headerDuplicateKey)
        }
        assertRule(plain + repeated + tooDeep + "}\n" + goodLine, .headerDuplicateKey)
        assertRule(plain + tooDeep + repeated + "}\n" + goodLine, .headerJSON)
        assertRule(plain + ",\"z\":" + String(repeating: "[", count: 30) + "{\"a\":1,\"a\":2}" + String(repeating: "]", count: 30) + "}\n" + goodLine, .headerDuplicateKey)
        assertRule(plain + repeated + ",\"r\":{\"b\":1,\"b\":2}}\n" + goodLine, .headerDuplicateKey)
        assertRule(plain + repeated + "}  \n" + goodLine, .headerDuplicateKey)
        assertRule(plain + repeated + "} {}\n" + goodLine, .headerJSON)
        assertRule(plain + repeated + "}\0\n" + goodLine, .headerJSON)
    }

    func testKeysWithALoneSurrogateCompareByTheirEscapes() {
        let plain = String(header().dropLast(2))
        assertRule(plain + ",\"q\":{\"\\ud800\":1,\"\\ud800\":2}}\n" + goodLine, .headerDuplicateKey)
        assertRule(plain + ",\"q\":{\"\\ud800\":1,\"\\ud801\":2}}\n" + goodLine, .headerJSON)
        assertRule(plain + ",\"q\":{\"\\ud83d\\ude00\":1,\"\u{1F600}\":2}}\n" + goodLine, .headerDuplicateKey)
    }

    func testSyntaxInsideNestingPastTheLimitStillDecidesTheRule() {
        let plain = String(header().dropLast(2)) + ",\"q\":1,\"q\":2,\"z\":"
        func nested(_ inner: String) -> String {
            return String(repeating: "[", count: 33) + inner + String(repeating: "]", count: 33) + "}\n" + goodLine
        }
        let wellFormed = [
            "", "1", " 1 ", "\"s\"", "true", "null", "[]", "{}", "[ ]", "{ }", "[1,2]", "[ 1 , 2 ]", "{\"a\":1}", "{ \"a\" : 1 , \"b\" : [] }",
            "{\"a\":1,\"a\":2}", "[{},[]]", "{\"a\":[{\"b\":{}}]}", "\"]}\"", "1e999", "\"\\ud800\""
        ]
        for inner in wellFormed {
            assertRule(plain + nested(inner), .headerDuplicateKey)
        }
        let malformed = [
            "1,", ",1", "1 2", "[1,]", "[,]", "{,}", "{\"a\"}", "{\"a\":}", "{\"a\":1,}", "{\"a\" 1}", "{1:2}", "{\"a\":1 \"b\":2}",
            "[}", "{]", "[1}", "{\"a\":1]", "]", "}", "\"", "\"\\q\"", "\"\u{1}\"", "01", "tru", "@"
        ]
        for inner in malformed {
            assertRule(plain + nested(inner), .headerJSON)
        }
        assertRule(plain + String(repeating: "[", count: 33) + "\n" + goodLine, .headerJSON)
        assertRule(plain + String(repeating: "{\"k\":", count: 33) + "\n" + goodLine, .headerJSON)
    }

    func testANumberIsJudgedByTheValueItDenotes() {
        let plain = String(header().dropLast(2))
        let denotes1e308 = "0." + String(repeating: "0", count: 98) + "1e407"
        let denotes1e309 = "1" + String(repeating: "0", count: 1000) + "e-691"
        XCTAssertNoThrow(try PublishedTimetable(data: Data((plain + ",\"z\":" + denotes1e308 + "}\n" + goodLine).utf8)))
        assertRule(plain + ",\"z\":" + denotes1e309 + "}\n" + goodLine, .headerJSON)
    }

    func testNestingTooDeepForRecursionIsRejectedWithoutACrash() {
        let plain = String(header().dropLast(2))
        let depth = 200_000
        let closed = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        assertRule(plain + ",\"z\":" + closed + "}\n" + goodLine, .headerJSON)
        assertRule(plain + ",\"q\":1,\"q\":2,\"z\":" + closed + "}\n" + goodLine, .headerDuplicateKey)
        assertRule(plain + ",\"q\":1,\"q\":2,\"z\":" + closed + "\n" + goodLine, .headerJSON)
    }

    func testAScalarInsideTheThirtySecondLevelIsAccepted() {
        func nested(_ open: String, _ close: String, containers: Int, innermost: String) -> String {
            return header(fields: fields(revision: "1") + ",\"deep\":" + String(repeating: open, count: containers - 1) + innermost + String(repeating: close, count: containers - 1))
        }
        XCTAssertNoThrow(try timetable(nested("[", "]", containers: 31, innermost: "[1,\"s\"]"), goodLine))
        XCTAssertNoThrow(try timetable(nested("{\"k\":", "}", containers: 31, innermost: "{\"n\":1,\"s\":\"s\"}"), goodLine))
        assertHeaderRule(nested("[", "]", containers: 32, innermost: "[1,\"s\"]"), .headerJSON)
        assertHeaderRule(nested("{\"k\":", "}", containers: 32, innermost: "{\"n\":1,\"s\":\"s\"}"), .headerJSON)
    }

    func testAByteOrderMarkIsMalformedWhereverItSits() {
        let bom = "\u{FEFF}"
        assertRule(bom + header() + goodLine, .fileBOM)
        assertRule(header().replacingOccurrences(of: "OTT 1\n{", with: "OTT 1\n\(bom){") + goodLine, .fileBOM)
        assertRule(header() + bom + goodLine, .fileBOM)
        assertRule(header() + goodLine.replacingOccurrences(of: " 0300", with: " \(bom)0300"), .fileBOM)
        assertRule(header(goodNames: "{\"en\":\"\(bom)Good\"}") + goodLine, .fileBOM)
        assertRule((header() + goodLine).replacingOccurrences(of: "\n", with: "\r\n"), .fileCR)
    }

    func testTheEscapeForABOMInsideAHeaderStringIsAccepted() {
        XCTAssertNoThrow(try timetable(header(goodNames: "{\"en\":\"A\\ufeffB\"}"), goodLine))
    }

    func testAuthorityAndPartMatchTheTokenPattern() {
        for authority in ["Xx", "xx_y", "-xx", "xx.y", "", "xx y", String(repeating: "x", count: 65)] {
            assertHeaderRule(header(fields: "\"authority\":\"\(authority)\",\"revision\":1,\"part\":\"all\""), .headerAuthority)
        }
        for part in ["All", "a/b", "", "al l"] {
            assertHeaderRule(header(fields: "\"authority\":\"xx\",\"revision\":1,\"part\":\"\(part)\""), .headerPart)
        }
        XCTAssertNoThrow(try timetable(header(fields: "\"authority\":\"sa-umm-al-qura\",\"revision\":1,\"part\":\"\(String(repeating: "p", count: 64))\""), goodLine))
    }

    func testARingIsCheckedForWidthThenCountThenRange() throws {
        assertHeaderRule(header(goodGeometry: area("_gjaR_gjaR~bidP")), .localityAreaRing)
        assertHeaderRule(header(goodGeometry: area("_gjaR_gjaR_c`|@_c`|@")), .localityAreaRing)
        assertHeaderRule(header(goodGeometry: area("_gjaR_gjaR_ws|k~B?~rr_j~B_c`|@")), .localityAreaVertex)
        assertHeaderRule(header(goodGeometry: area("_gjaR_gjaR_______C?~z}a}~~B_c`|@")), .localityAreaPolyline)
        let thirteenChunks = "}" + String(repeating: "~", count: 11) + "F"
        assertHeaderRule(header(goodGeometry: area([String](repeating: thirteenChunks + "?", count: 3).joined())), .localityAreaPolyline)
        assertHeaderRule(header(goodGeometry: area("_gjaR_gjaR_s~baD?~n}e_D_gjaR")), .localityAreaVertex)
        assertHeaderRule(header(goodGeometry: area("__lhkA__lhkA_c`|@??_c`|@~b`|@?}~~~~~B?")), .localityAreaVertex)
        assertHeaderRule(header(goodGeometry: area("}~~~~~B?}~~~~~B??_c`|@")), .localityAreaVertex)
        assertHeaderRule(header(goodGeometry: area("__lhkA__lhkA_c`|@??_c`|@~b`|@?`_____C?")), .localityAreaPolyline)
        assertHeaderRule(header(goodGeometry: area("__lhkA__lhkA_c`|@??_c`|@~b`|@?`_____C")), .localityAreaPolyline)
        assertHeaderRule(header(goodGeometry: area("")), .localityAreaPolyline)
        XCTAssertNoThrow(try timetable(header(goodGeometry: area("_gjaR_gjaR_c`|@??_c`|@")), goodLine))
    }

    func testALookupAtAReferencePointsAntipodeIsNoLocality() throws {
        let timetable = try self.timetable(locality("{\"id\":\"bad\",\"group\":\"g\",\"zone\":0,\"names\":{},\"ref\":[30659338,-53232634],\"point\":{\"radiusM\":1000}}"), goodLine)
        guard case .noLocality = try timetable.lookup(Coordinates(latitude: -30.659338, longitude: 126.767366), on: january1) else {
            return XCTFail("the antipode of a point locality resolved to a locality")
        }
        XCTAssertEqual(LocalityIndex.haversineMm(30.659338, -53.232634, -30.659338, 126.767366), Int64((Double.pi * 6371008.8 * 1000).rounded()))
    }

    func testTheHanafiShiftRoundsHalfMinutesUp() {
        XCTAssertEqual(PrayerTimes.shiftMinutes(fromHours: -37.5 / 60), -37)
        XCTAssertEqual(PrayerTimes.shiftMinutes(fromHours: 37.5 / 60), 38)
        XCTAssertEqual(PrayerTimes.shiftMinutes(fromHours: -7.5 / 60), -7)
        XCTAssertEqual(PrayerTimes.shiftMinutes(fromHours: 22.5 / 60), 23)
        XCTAssertEqual(PrayerTimes.shiftMinutes(fromHours: -37.4 / 60), -37)
        XCTAssertEqual(PrayerTimes.shiftMinutes(fromHours: -37.6 / 60), -38)
    }

    func testAShiftBeyondThirtyTwoBitsIsUndefined() {
        XCTAssertEqual(PrayerTimes.shiftMinutes(fromHours: 2147483647.0 / 60), 2147483647)
        XCTAssertEqual(PrayerTimes.shiftMinutes(fromHours: -2147483648.0 / 60), -2147483648)
        XCTAssertNil(PrayerTimes.shiftMinutes(fromHours: 2147483648.0 / 60))
        XCTAssertNil(PrayerTimes.shiftMinutes(fromHours: -2147483649.0 / 60))
    }

    func testTheTimetableKeepsItsOwnBytes() throws {
        var bytes = try PublishedVectors.data("valid/kacst-like.ott")
        let timetable = try PublishedTimetable(data: bytes)
        bytes.resetBytes(in: 0..<bytes.count)
        XCTAssertEqual(bytes.first, 0)
        guard case .published(let row) = try timetable.lookup(Coordinates(latitude: 24.7136, longitude: 46.6753), on: january1) else {
            return XCTFail("Riyadh gave no row after the caller zeroed its copy")
        }
        XCTAssertEqual(row.published(.fajr), PublishedVectors.instant("2026-01-01T02:14:00Z"))
        XCTAssertNoThrow(try timetable.validateAllRows())
    }

    func testAMappedFileDecodes() throws {
        let url = PublishedVectors.directory.appendingPathComponent("valid/kacst-like.ott")
        let timetable = try PublishedTimetable(data: try Data(contentsOf: url, options: .alwaysMapped))
        guard case .published(let row) = try timetable.lookup(Coordinates(latitude: 24.7136, longitude: 46.6753), on: january1) else {
            return XCTFail("Riyadh gave no row")
        }
        XCTAssertEqual(row.published(.fajr), PublishedVectors.instant("2026-01-01T02:14:00Z"))
        XCTAssertNoThrow(try timetable.validateAllRows())
    }

    func testADateFarPastTheLastLineIsNoRow() throws {
        let timetable = try PublishedVectors.timetable("valid/kacst-like.ott")
        guard case .noRow(let locality) = try timetable.lookup(Coordinates(latitude: 24.7136, longitude: 46.6753), on: DateComponents(year: 2_000_000, month: 1, day: 1), localityId: LocalityId("1001")) else {
            return XCTFail("a date in the year 2000000 gave something other than noRow")
        }
        XCTAssertEqual(locality.id, LocalityId("1001"))
    }

    func testConcurrentFirstDecodesOnAFreshInstanceMatchASeparateInstance() throws {
        let data = try PublishedVectors.data("valid/kacst-like.ott")
        let reference = try PublishedTimetable(data: data)
        let places = [Coordinates(latitude: 24.7136, longitude: 46.6753), Coordinates(latitude: 21.4225, longitude: 39.8262), Coordinates(latitude: 24.54, longitude: 39.63), Coordinates(latitude: 0, longitude: 0)]
        let query: @Sendable (PublishedTimetable, Int) -> String = { timetable, iteration in
            let date = DateComponents(year: 2026 + iteration % 2, month: 1, day: 1 + iteration % 12)
            switch try! timetable.lookup(places[iteration % places.count], on: date) {
            case .published(let row):
                return "\(row.locality.id) \(row.published(.isha)!.timeIntervalSince1970)"
            case .noRow(let locality):
                return "noRow \(locality.id)"
            case .noLocality:
                return "noLocality"
            }
        }
        let expected = (0..<200).map { query(reference, $0) }
        for round in 0..<20 {
            let shared = try PublishedTimetable(data: data)
            let results = ThreadResults()
            DispatchQueue.concurrentPerform(iterations: 8) { thread in
                results.record(thread, (0..<200).map { query(shared, ($0 + thread * 7) % 200) })
            }
            for thread in 0..<8 {
                XCTAssertEqual(results.values[thread], (0..<200).map { expected[($0 + thread * 7) % 200] }, "round \(round) thread \(thread)")
            }
        }
    }

    func testADateThatIsNoDayIsACallerError() throws {
        let timetable = try PublishedVectors.timetable("valid/kacst-like.ott")
        let riyadh = Coordinates(latitude: 24.7136, longitude: 46.6753)
        for date in [DateComponents(year: 2026, month: 2), DateComponents(year: 2026, month: 2, day: 30), DateComponents(year: 2_147_483_648, month: 1, day: 1)] {
            XCTAssertThrowsError(try timetable.localityAt(riyadh, on: date), "\(date)") { error in
                XCTAssertEqual(error as? OfficialLookupError, .invalidDate(date))
            }
            XCTAssertThrowsError(try timetable.lookup(riyadh, on: date), "\(date)") { error in
                XCTAssertEqual(error as? OfficialLookupError, .invalidDate(date))
            }
            XCTAssertThrowsError(try timetable.lookup(riyadh, on: date, localityId: LocalityId("1001")), "\(date)") { error in
                XCTAssertEqual(error as? OfficialLookupError, .invalidDate(date))
            }
        }
    }
}

private final class ThreadResults: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [Int: [String]]()

    func record(_ thread: Int, _ results: [String]) {
        lock.lock()
        storage[thread] = results
        lock.unlock()
    }

    var values: [Int: [String]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
