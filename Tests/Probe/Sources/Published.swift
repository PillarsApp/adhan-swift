import Adhan
import Dispatch
import Foundation

func loadTimetable(_ path: String) -> PublishedTimetable {
    do {
        return try PublishedTimetable(data: try Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped))
    } catch {
        FileHandle.standardError.write("cannot decode \(path): \(error)\n".data(using: .utf8)!)
        exit(2)
    }
}

func utcISO(_ date: Date) -> String {
    let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", comps.year!, comps.month!, comps.day!, comps.hour!, comps.minute!, comps.second!)
}

func coveredDays(_ timetable: PublishedTimetable) -> [(label: String, components: DateComponents)] {
    let coverage = timetable.coverage
    let start = calendar.date(from: coverage.from)!
    let end = calendar.date(from: coverage.to)!
    var out = [(label: String, components: DateComponents)]()
    var day = start
    while day <= end {
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        out.append((label(comps), comps))
        day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return out
}

func dumpOfficial(_ path: String) -> String {
    let timetable = loadTimetable(path)
    do {
        try timetable.validateAllRows()
    } catch {
        FileHandle.standardError.write("validateAllRows failed: \(error)\n".data(using: .utf8)!)
        exit(2)
    }
    var out = ""
    for locality in timetable.localities {
        let id = locality.id.rawValue
        for day in coveredDays(timetable) {
            switch try! timetable.lookup(locality.referencePoint, on: day.components, localityId: locality.id) {
            case .noLocality:
                out += "N\t\(id)\t\(day.label)\tNoLocality\n"
            case .noRow:
                out += "N\t\(id)\t\(day.label)\tNoRow\n"
            case .published(let row):
                for column in timetable.columns {
                    out += "P\t\(id)\t\(day.label)\t\(column.rawValue)\t\(utcISO(row.published(column)!))\n"
                }
                for madhab in [Madhab.shafi, .hanafi] {
                    var parameters = CalculationMethod.ummAlQura.params
                    parameters.madhab = madhab
                    let name = madhab == .shafi ? "shafi" : "hanafi"
                    guard let times = PrayerTimes(official: row, parameters: parameters) else {
                        out += "A\t\(id)\t\(day.label)\t\(name)\tnil\n"
                        continue
                    }
                    let six = [times.fajr, times.sunrise, times.dhuhr, times.asr, times.maghrib, times.isha].map(utcISO)
                    out += "A\t\(id)\t\(day.label)\t\(name)\t\(six.joined(separator: "\t"))\n"
                }
            }
        }
    }
    return out
}

func resolveOfficial(_ path: String) -> String {
    let timetable = loadTimetable(path)
    let input = FileHandle.standardInput.readDataToEndOfFile()
    var out = ""
    for line in String(decoding: input, as: UTF8.self).split(separator: "\n") {
        let parts = line.split(separator: ",")
        let date = parts[2].split(separator: "-").map { Int($0)! }
        let point = Coordinates(latitude: Double(parts[0])!, longitude: Double(parts[1])!)
        let locality = try! timetable.localityAt(point, on: DateComponents(year: date[0], month: date[1], day: date[2]))
        out += "\(line),\(locality?.id.rawValue ?? "nil")\n"
    }
    return out
}

func benchPublished(_ path: String) {
    let data = try! Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped)
    let riyadh = Coordinates(latitude: 24.7136, longitude: 46.6753)
    let date = DateComponents(year: 2027, month: 2, day: 8)
    let repeated = 10_000
    func elapsedMilliseconds(_ work: () -> Void) -> Double {
        let started = DispatchTime.now().uptimeNanoseconds
        work()
        return Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }
    var initSamples = [Double]()
    var firstSamples = [Double]()
    var repeatedSamples = [Double]()
    var validateSamples = [Double]()
    for _ in 0..<5 {
        var timetable: PublishedTimetable! = nil
        initSamples.append(elapsedMilliseconds { timetable = try! PublishedTimetable(data: data) })
        firstSamples.append(elapsedMilliseconds {
            guard case .published = try! timetable.lookup(riyadh, on: date) else {
                fatalError("expected a row")
            }
        })
        repeatedSamples.append(elapsedMilliseconds {
            for i in 0..<repeated {
                let day = DateComponents(year: 2026 + i % 2, month: 1 + i % 12, day: 1 + i % 28)
                guard case .published = try! timetable.lookup(riyadh, on: day) else {
                    fatalError("expected a row")
                }
            }
        })
        validateSamples.append(elapsedMilliseconds { try! PublishedTimetable(data: data).validateAllRows() })
    }
    func median(_ samples: [Double]) -> Double {
        return samples.sorted()[samples.count / 2]
    }
    print("artifact bytes: \(data.count)")
    print("bench,init_ms,\(String(format: "%.3f", median(initSamples)))")
    print("bench,first_lookup_ms,\(String(format: "%.3f", median(firstSamples)))")
    print("bench,repeated_lookup_us,\(String(format: "%.3f", median(repeatedSamples) * 1_000 / Double(repeated)))")
    print("bench,validate_all_rows_ms,\(String(format: "%.3f", median(validateSamples)))")
    print("samples init ms: \(initSamples.map { String(format: "%.3f", $0) }.joined(separator: " "))")
    print("samples first lookup ms: \(firstSamples.map { String(format: "%.3f", $0) }.joined(separator: " "))")
}
