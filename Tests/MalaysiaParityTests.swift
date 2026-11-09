import XCTest
@testable import Adhan

class MalaysiaParityTests: XCTestCase {
    private static let goldenPath = "Resources/malaysia/golden_ab967ec.tsv"
    private static let header = "zone\tmadhab\toffsets\tmode\tfnv1a64"

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

    func testLegacyMalaysiaOutputMatchesTheGolden() throws {
        let environment = ProcessInfo.processInfo.environment
        let recordPath = environment["ADHAN_RECORD_MALAYSIA_GOLDEN"]
        let fullPath = environment["ADHAN_MALAYSIA_GOLDEN_FULL"]

        var head = [(key: String, digest: String)]()
        var fullOutput = ""
        MalaysiaGolden.forEachGroup { group in
            head.append((group.key, group.digest))
            if fullPath != nil {
                for line in group.lines {
                    fullOutput += "\(group.key)\t\(line)\n"
                }
            }
        }

        if let fullPath {
            try fullOutput.write(toFile: fullPath, atomically: true, encoding: .utf8)
        }
        if let recordPath {
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
            return (fields[0..<4].joined(separator: "\t"), String(fields[4]))
        }

        XCTAssertEqual(golden.count, 828)
        XCTAssertEqual(head.count, 828)
        XCTAssertEqual(head.map(\.key), golden.map(\.key))

        let expected = Dictionary(golden.map { ($0.key, $0.digest) }, uniquingKeysWith: { first, _ in first })
        let changed = head.filter { expected[$0.key] != $0.digest }.map { $0.key.replacingOccurrences(of: "\t", with: " ") }
        XCTAssertEqual(changed, [], "\(changed.count) group(s) differ from the golden: \(changed.prefix(20).joined(separator: "; "))")
    }
}
