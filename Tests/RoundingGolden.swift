import Foundation
@testable import Adhan

enum RoundingGolden {
    static let cities: [(name: String, latitude: Double, longitude: Double)] = [
        ("KualaLumpur", 3.1390, 101.6869),
        ("London", 51.5074, -0.1278),
        ("NewYork", 40.7128, -74.0060),
        ("Oslo", 59.9139, 10.7522),
        ("Reykjavik", 64.1466, -21.9426),
        ("Sydney", -33.8688, 151.2093),
        ("Tromso", 69.6492, 18.9553),
        ("Auckland", -36.8485, 174.7633),
        ("Apia", -13.8333, -171.7500),
        ("BuenosAires", -34.6037, -58.3816),
        ("Suva", -18.1416, 178.4419),
        ("ChathamIslands", -43.95, -176.55),
        ("Riyadh", 24.7136, 46.6753),
        ("Mecca", 21.4225, 39.8262),
    ]

    static var roundings: [Rounding] { [.nearest, .up, .none] }

    static let days: [DateComponents] = {
        let calendar = Calendar.gregorianUTC
        let start = DateComponents(calendar: calendar, year: 2026, month: 1, day: 1).date!
        return (0..<365).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            return calendar.dateComponents([.year, .month, .day], from: day)
        }
    }()

    struct Group {
        let key: String
        let lines: [String]

        var digest: String {
            return MalaysiaGolden.fnv1a64Hex(lines.joined(separator: "\n"))
        }
    }

    static func forEachGroup(_ body: (Group) -> Void) {
        for city in cities {
            let coordinates = Coordinates(latitude: city.latitude, longitude: city.longitude)
            for method in CalculationMethod.allCases {
                for rounding in roundings {
                    var parameters = method.params
                    parameters.rounding = rounding
                    let lines = days.map { line(day: $0, coordinates: coordinates, parameters: parameters) }
                    body(Group(key: [city.name, method.rawValue, rounding.rawValue].joined(separator: "\t"), lines: lines))
                }
            }
        }
    }

    static func line(day: DateComponents, coordinates: Coordinates, parameters: CalculationParameters) -> String {
        let date = String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!)
        guard let times = PrayerTimes(coordinates: coordinates, date: day, calculationParameters: parameters) else {
            return [date, "nil"].joined(separator: "\t")
        }
        let sunnah = SunnahTimes(from: times).map { [MalaysiaGolden.iso($0.middleOfTheNight), MalaysiaGolden.iso($0.lastThirdOfTheNight)] } ?? ["nil", "nil"]
        return ([date] + [times.fajr, times.sunrise, times.dhuhr, times.asr, times.maghrib, times.isha].map(MalaysiaGolden.iso) + sunnah)
            .joined(separator: "\t")
    }
}
