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

let methodKeys = ["mwl_mid", "mwl_seventh", "mwl_twilight", "msc_mid", "isna_mid", "singapore_mid"]

struct Options {
    var polarCircleResolution: PolarCircleResolution?
    var hourAngleCorrection: HourAngleCorrection?
    var bench = false
}

func usage() -> Never {
    let text = """
    usage: Probe [--polar aqrabBalad|aqrabYaum|unresolved] [--correction iterative|singlePass] [--bench]

    Without --bench, prints the 12 city, 365 day, 6 method grid for 2026 as CSV:
    city,date,method,fajr,sunrise,dhuhr,asr,maghrib,isha (UTC epoch seconds, or nil).
    The first ten cities are the original grid; Suva and ChathamIslands sit near ±180°.
    With --bench, prints the median microseconds per PrayerTimes construction for
    London Muslim World League over 100,000 constructions.

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

let calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

let days2026: [(label: String, components: DateComponents)] = {
    let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    return (0..<365).map { offset in
        let day = calendar.date(byAdding: .day, value: offset, to: start)!
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        let label = String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
        return (label, comps)
    }
}()

func grid(_ options: Options) -> String {
    var out = ""
    for city in cities {
        for day in days2026 {
            for key in methodKeys {
                if let t = PrayerTimes(coordinates: city.coordinates, date: day.components, calculationParameters: params(key, options)) {
                    let values = [t.fajr, t.sunrise, t.dhuhr, t.asr, t.maghrib, t.isha].map { String(Int($0.timeIntervalSince1970)) }
                    out += "\(city.name),\(day.label),\(key),\(values.joined(separator: ","))\n"
                } else {
                    out += "\(city.name),\(day.label),\(key),nil,nil,nil,nil,nil,nil\n"
                }
            }
        }
    }
    return out
}

func benchMedianMicroseconds(_ options: Options) -> Double {
    let london = cities[1]
    let parameters = params("mwl_mid", options)
    let constructions = 100_000
    var samples = [Double]()
    samples.reserveCapacity(constructions)
    var checksum = 0.0
    for i in 0..<constructions {
        let components = days2026[i % days2026.count].components
        let started = DispatchTime.now().uptimeNanoseconds
        let times = PrayerTimes(coordinates: london.coordinates, date: components, calculationParameters: parameters)
        let finished = DispatchTime.now().uptimeNanoseconds
        checksum += times?.fajr.timeIntervalSince1970 ?? 0
        samples.append(Double(finished - started) / 1_000)
    }
    precondition(checksum > 0, "every London construction must succeed")
    samples.sort()
    return samples[samples.count / 2]
}

let options = parse(CommandLine.arguments)
if options.bench {
    let median = benchMedianMicroseconds(options)
    print("bench,London,mwl_mid,median_us,\(String(format: "%.3f", median))")
} else {
    FileHandle.standardOutput.write(grid(options).data(using: .utf8)!)
}
