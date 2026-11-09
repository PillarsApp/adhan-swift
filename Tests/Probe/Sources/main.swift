import Adhan
import Dispatch
import Foundation

struct City {
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinates: Coordinates {
        return Coordinates(latitude: latitude, longitude: longitude)
    }
}

let cities: [City] = [
    City(name: "KualaLumpur", latitude: 3.1390, longitude: 101.6869),
    City(name: "London", latitude: 51.5074, longitude: -0.1278),
    City(name: "NewYork", latitude: 40.7128, longitude: -74.0060),
    City(name: "Oslo", latitude: 59.9139, longitude: 10.7522),
    City(name: "Reykjavik", latitude: 64.1466, longitude: -21.9426),
    City(name: "Sydney", latitude: -33.8688, longitude: 151.2093),
    City(name: "Tromso", latitude: 69.6492, longitude: 18.9553),
    City(name: "Auckland", latitude: -36.8485, longitude: 174.7633),
    City(name: "Apia", latitude: -13.8333, longitude: -171.7500),
    City(name: "BuenosAires", latitude: -34.6037, longitude: -58.3816),
    City(name: "Suva", latitude: -18.1416, longitude: 178.4419),
    City(name: "ChathamIslands", latitude: -43.95, longitude: -176.55),
]

let malaysianCities: [City] = [
    City(name: "KualaLumpur", latitude: 3.1390, longitude: 101.6869),
    City(name: "KotaKinabalu", latitude: 5.9749, longitude: 116.0724),
    City(name: "JohorBahru", latitude: 1.4655, longitude: 103.7578),
    City(name: "Kuching", latitude: 1.5535, longitude: 110.3593),
    City(name: "GeorgeTown", latitude: 5.4164, longitude: 100.3327),
    City(name: "ShahAlam", latitude: 3.0733, longitude: 101.5185),
]

let methodKeys = ["mwl_mid", "mwl_seventh", "mwl_twilight", "msc_mid", "isna_mid", "singapore_mid"]

let malaysiaYears = [2026, 2027]

struct Options {
    var polarCircleResolution: PolarCircleResolution?
    var hourAngleCorrection: HourAngleCorrection?
    var bench = false
    var malaysiaAllZones = false
    var malaysiaResolve: String?
    var malaysiaHanafi = false
    var benchMalaysia = false
    var dumpOfficial: String?
    var resolveOfficial: String?
    var benchPublished: String?
}

func usage() -> Never {
    let text = """
    usage: Probe [--polar aqrabBalad|aqrabYaum|unresolved] [--correction iterative|singlePass] [--bench]
           Probe --malaysia-all-zones | --malaysia-resolve <file> | --malaysia-hanafi | --bench-malaysia
           Probe --dump-official <ott> | --resolve-official <ott> | --bench-published <ott>

    Without --bench, prints the 12 city, 365 day, 6 method grid for 2026 as CSV:
    city,date,method,fajr,sunrise,dhuhr,asr,maghrib,isha (UTC epoch seconds, or nil).
    The first ten cities are the original grid; Suva and ChathamIslands sit near ±180°.
    With --bench, prints the median microseconds per PrayerTimes construction for
    London Muslim World League over 100,000 constructions.

    --malaysia-all-zones prints, for every zone in force on 1 June 2026 or 2027 and
    every day of those years that has a row:
    zone,date,source,fajr,sunrise,dhuhr,asr,maghrib,isha,imsak,subuh,syuruk,dhuha,zohor,asar,maghrib,isyak
    with the six from PrayerTimes at the zone's reference point with the manual zone
    and the eight from MalaysiaTimetable.day, as UTC epoch seconds.
    --malaysia-resolve reads lat,lon,yyyy-mm-dd lines and appends the resolved zone code or nil.
    --malaysia-hanafi prints zone,date,correction,shafiAsr,hanafiAsr on the 15th of
    January, April, July and October of each year, for each hour angle correction.
    --bench-malaysia prints the cold first lookup in ms and the warm medians in µs.
    --dump-official decodes an OTT 1 file and prints, for every locality and covered day,
    P,id,date,column,instant per published column and A,id,date,madhab,six instants from
    PrayerTimes(official:) with the Umm al-Qura preset, or N,id,date,kind for a day without a row.
    --resolve-official reads lat,lon,yyyy-mm-dd lines on stdin and appends the locality id or nil.
    --bench-published prints init, first lookup, repeated lookup and validateAllRows timings.

    """
    FileHandle.standardError.write(text.data(using: .utf8)!)
    exit(2)
}

func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var rest = arguments.dropFirst()
    while let flag = rest.popFirst() {
        switch flag {
        case "--polar":
            guard let raw = rest.popFirst(), let value = PolarCircleResolution(rawValue: raw) else {
                usage()
            }
            options.polarCircleResolution = value
        case "--correction":
            guard let raw = rest.popFirst(), let value = HourAngleCorrection(rawValue: raw) else {
                usage()
            }
            options.hourAngleCorrection = value
        case "--bench":
            options.bench = true
        case "--malaysia-all-zones":
            options.malaysiaAllZones = true
        case "--malaysia-resolve":
            guard let path = rest.popFirst() else {
                usage()
            }
            options.malaysiaResolve = path
        case "--malaysia-hanafi":
            options.malaysiaHanafi = true
        case "--bench-malaysia":
            options.benchMalaysia = true
        case "--dump-official":
            guard let path = rest.popFirst() else {
                usage()
            }
            options.dumpOfficial = path
        case "--resolve-official":
            guard let path = rest.popFirst() else {
                usage()
            }
            options.resolveOfficial = path
        case "--bench-published":
            guard let path = rest.popFirst() else {
                usage()
            }
            options.benchPublished = path
        default:
            usage()
        }
    }
    return options
}

func params(_ key: String, _ options: Options) -> CalculationParameters {
    var p: CalculationParameters
    switch key {
    case "mwl_mid":
        p = CalculationMethod.muslimWorldLeague.params
        p.highLatitudeRule = .middleOfTheNight
    case "mwl_seventh":
        p = CalculationMethod.muslimWorldLeague.params
        p.highLatitudeRule = .seventhOfTheNight
    case "mwl_twilight":
        p = CalculationMethod.muslimWorldLeague.params
        p.highLatitudeRule = .twilightAngle
    case "msc_mid":
        p = CalculationMethod.moonsightingCommittee.params
        p.highLatitudeRule = .middleOfTheNight
    case "isna_mid":
        p = CalculationMethod.northAmerica.params
        p.highLatitudeRule = .middleOfTheNight
    case "singapore_mid":
        p = CalculationMethod.singapore.params
        p.highLatitudeRule = .middleOfTheNight
    default:
        fatalError(key)
    }
    if let resolution = options.polarCircleResolution {
        p.polarCircleResolution = resolution
    }
    if let correction = options.hourAngleCorrection {
        p.hourAngleCorrection = correction
    }
    return p
}

func malaysiaParams(zone: String? = nil, madhab: Madhab = .shafi, correction: HourAngleCorrection = .iterative) -> CalculationParameters {
    var p = CalculationMethod.malaysiaOfficial.params
    p.malaysiaZone = zone
    p.madhab = madhab
    p.hourAngleCorrection = correction
    return p
}

let calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

func label(_ comps: DateComponents) -> String {
    return String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
}

func days(of year: Int) -> [(label: String, components: DateComponents)] {
    let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
    return (0..<365).map { offset in
        let day = calendar.date(byAdding: .day, value: offset, to: start)!
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        return (label(comps), comps)
    }
}

let days2026 = days(of: 2026)

func epoch(_ date: Date) -> String {
    return String(Int(date.timeIntervalSince1970))
}

func grid(_ options: Options) -> String {
    var out = ""
    for city in cities {
        for day in days2026 {
            for key in methodKeys {
                if let t = PrayerTimes(coordinates: city.coordinates, date: day.components, calculationParameters: params(key, options)) {
                    let values = [t.fajr, t.sunrise, t.dhuhr, t.asr, t.maghrib, t.isha].map(epoch)
                    out += "\(city.name),\(day.label),\(key),\(values.joined(separator: ","))\n"
                } else {
                    out += "\(city.name),\(day.label),\(key),nil,nil,nil,nil,nil,nil\n"
                }
            }
        }
    }
    return out
}

let constructions = 100_000

func medianMicroseconds(_ work: (Int) -> Double) -> Double {
    var samples = [Double]()
    samples.reserveCapacity(constructions)
    var checksum = 0.0
    for i in 0..<constructions {
        let started = DispatchTime.now().uptimeNanoseconds
        let value = work(i)
        let finished = DispatchTime.now().uptimeNanoseconds
        checksum += value
        samples.append(Double(finished - started) / 1_000)
    }
    precondition(checksum > 0, "every construction must succeed")
    samples.sort()
    return samples[samples.count / 2]
}

func benchMedianMicroseconds(_ options: Options) -> Double {
    let london = cities[1]
    let parameters = params("mwl_mid", options)
    return medianMicroseconds { i in
        let times = PrayerTimes(coordinates: london.coordinates, date: days2026[i % days2026.count].components, calculationParameters: parameters)
        return times?.fajr.timeIntervalSince1970 ?? 0
    }
}

func malaysiaCatalog() -> [MalaysiaZone] {
    var seen = [String: MalaysiaZone]()
    for year in malaysiaYears {
        for zone in MalaysiaZones.on(DateComponents(year: year, month: 6, day: 1)) {
            seen[zone.code] = zone
        }
    }
    return seen.keys.sorted().map { seen[$0]! }
}

func malaysiaAllZones() -> String {
    var out = ""
    for zone in malaysiaCatalog() {
        let parameters = malaysiaParams(zone: zone.code)
        for year in malaysiaYears {
            for day in days(of: year) {
                guard let row = MalaysiaTimetable.day(zone, on: day.components) else {
                    continue
                }
                var cells = [zone.code, day.label]
                if let times = PrayerTimes(coordinates: zone.referencePoint, date: day.components, calculationParameters: parameters) {
                    cells.append("\(times.source)")
                    cells += [times.fajr, times.sunrise, times.dhuhr, times.asr, times.maghrib, times.isha].map(epoch)
                } else {
                    cells += Array(repeating: "nil", count: 7)
                }
                cells += [row.imsak, row.subuh, row.syuruk, row.dhuha, row.zohor, row.asar, row.maghrib, row.isyak].map(epoch)
                out += cells.joined(separator: ",") + "\n"
            }
        }
    }
    return out
}

func malaysiaResolve(_ path: String) -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
        exit(2)
    }
    var out = ""
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: ",")
        let date = parts[2].split(separator: "-").map { Int($0)! }
        let point = Coordinates(latitude: Double(parts[0])!, longitude: Double(parts[1])!)
        let zone = MalaysiaZones.resolve(point, on: DateComponents(year: date[0], month: date[1], day: date[2]))
        out += "\(line),\(zone?.code ?? "nil")\n"
    }
    return out
}

func malaysiaHanafi() -> String {
    var out = ""
    for zone in malaysiaCatalog() {
        for year in malaysiaYears {
            for month in [1, 4, 7, 10] {
                let date = DateComponents(year: year, month: month, day: 15)
                for correction in HourAngleCorrection.allCases {
                    guard let shafi = PrayerTimes(coordinates: zone.referencePoint, date: date, calculationParameters: malaysiaParams(zone: zone.code, correction: correction)),
                        shafi.source == .official,
                        let hanafi = PrayerTimes(coordinates: zone.referencePoint, date: date, calculationParameters: malaysiaParams(zone: zone.code, madhab: .hanafi, correction: correction)) else {
                        continue
                    }
                    out += "\(zone.code),\(label(date)),\(correction.rawValue),\(epoch(shafi.asr)),\(epoch(hanafi.asr))\n"
                }
            }
        }
    }
    return out
}

func benchMalaysia() {
    let kualaLumpur = cities[0].coordinates
    let started = DispatchTime.now().uptimeNanoseconds
    let first = PrayerTimes(coordinates: kualaLumpur, date: DateComponents(year: 2026, month: 11, day: 2), calculationParameters: malaysiaParams())
    let finished = DispatchTime.now().uptimeNanoseconds
    precondition(first?.source == .official, "Kuala Lumpur must read an official row")
    print("bench,cold_first_lookup_ms,\(String(format: "%.3f", Double(finished - started) / 1_000_000))")

    func report(_ name: String, _ work: (Int) -> Double) {
        print("bench,\(name),\(String(format: "%.3f", medianMicroseconds(work)))")
    }

    let manual = malaysiaParams(zone: "WLY01")
    report("warm_lookup_us") { i in
        PrayerTimes(coordinates: kualaLumpur, date: days2026[i % days2026.count].components, calculationParameters: manual)?.fajr.timeIntervalSince1970 ?? 0
    }
    let automatic = malaysiaParams()
    report("warm_lookup_auto_us") { i in
        PrayerTimes(coordinates: kualaLumpur, date: days2026[i % days2026.count].components, calculationParameters: automatic)?.fajr.timeIntervalSince1970 ?? 0
    }
    report("zone_resolve_us") { i in
        let city = malaysianCities[i % malaysianCities.count]
        return Double(MalaysiaZones.resolve(city.coordinates, on: days2026[i % days2026.count].components)?.code.count ?? 0)
    }
    let london = cities[1].coordinates
    let mwl = params("mwl_mid", Options())
    report("existing_mwl_us") { i in
        PrayerTimes(coordinates: london, date: days2026[i % days2026.count].components, calculationParameters: mwl)?.fajr.timeIntervalSince1970 ?? 0
    }
}

let options = parse(CommandLine.arguments)
if let path = options.dumpOfficial {
    FileHandle.standardOutput.write(dumpOfficial(path).data(using: .utf8)!)
} else if let path = options.resolveOfficial {
    FileHandle.standardOutput.write(resolveOfficial(path).data(using: .utf8)!)
} else if let path = options.benchPublished {
    benchPublished(path)
} else if options.benchMalaysia {
    benchMalaysia()
} else if options.malaysiaAllZones {
    FileHandle.standardOutput.write(malaysiaAllZones().data(using: .utf8)!)
} else if let path = options.malaysiaResolve {
    FileHandle.standardOutput.write(malaysiaResolve(path).data(using: .utf8)!)
} else if options.malaysiaHanafi {
    FileHandle.standardOutput.write(malaysiaHanafi().data(using: .utf8)!)
} else if options.bench {
    let median = benchMedianMicroseconds(options)
    print("bench,London,mwl_mid,median_us,\(String(format: "%.3f", median))")
} else {
    FileHandle.standardOutput.write(grid(options).data(using: .utf8)!)
}
