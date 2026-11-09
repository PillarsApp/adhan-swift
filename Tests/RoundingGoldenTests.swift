import XCTest
@testable import Adhan

class RoundingGoldenTests: XCTestCase {
    private static let goldenPath = "Resources/rounding/golden_1a1b6e7.tsv"
    private static let header = "city\tmethod\trounding\tfnv1a64"

    private func goldenURL() -> URL {
        if let directory = Bundle.module.resourceURL {
            let bundled = directory.appendingPathComponent(Self.goldenPath)
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(Self.goldenPath)
    }

    func testEveryMethodKeepsTheTimesRecordedBeforeTheNewRounding() throws {
        var head = [(key: String, digest: String)]()
        RoundingGolden.forEachGroup { group in
            head.append((group.key, group.digest))
        }

        if let recordPath = ProcessInfo.processInfo.environment["ADHAN_RECORD_ROUNDING_GOLDEN"] {
            let rows = head.map { "\($0.key)\t\($0.digest)" }
            try ([Self.header] + rows).joined(separator: "\n").appending("\n")
                .write(toFile: recordPath, atomically: true, encoding: .utf8)
            return
        }

        let text = try String(contentsOf: goldenURL(), encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(lines.removeFirst(), Self.header)
        let golden = lines.map { line -> (key: String, digest: String) in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            return (fields[0..<3].joined(separator: "\t"), String(fields[3]))
        }

        XCTAssertEqual(golden.count, 630)
        XCTAssertEqual(head.map(\.key), golden.map(\.key))

        let expected = Dictionary(golden.map { ($0.key, $0.digest) }, uniquingKeysWith: { first, _ in first })
        let changed = head.filter { expected[$0.key] != $0.digest }.map { $0.key.replacingOccurrences(of: "\t", with: " ") }
        XCTAssertEqual(changed, [], "\(changed.count) group(s) differ from the golden: \(changed.prefix(20).joined(separator: "; "))")
    }
}
