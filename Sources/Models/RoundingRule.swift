import Foundation

internal enum MinuteRounding {
    case nearest
    case up
    case down
    case none
}

internal enum TimePrecision {
    case wholeSeconds
    case microseconds
}

internal struct RoundingRule {
    let precision: TimePrecision
    private let start: MinuteRounding
    private let sunrise: MinuteRounding

    init(_ rounding: Rounding) {
        switch rounding {
        case .nearest:
            self.init(precision: .wholeSeconds, start: .nearest, sunrise: .nearest)
        case .up:
            self.init(precision: .wholeSeconds, start: .up, sunrise: .up)
        case .none:
            self.init(precision: .wholeSeconds, start: .none, sunrise: .none)
        case .startsUpSunriseDown:
            self.init(precision: .microseconds, start: .up, sunrise: .down)
        }
    }

    private init(precision: TimePrecision, start: MinuteRounding, sunrise: MinuteRounding) {
        self.precision = precision
        self.start = start
        self.sunrise = sunrise
    }

    func roundedStart(_ date: Date) -> Date {
        rounded(date, start)
    }

    func roundedSunrise(_ date: Date) -> Date {
        rounded(date, sunrise)
    }

    func nightPortions(_ night: TimeInterval) -> (half: TimeInterval, lastThird: TimeInterval) {
        switch precision {
        case .wholeSeconds:
            return (night / 2, night * (2 / 3))
        case .microseconds:
            let micros = Int64((night * 1_000_000).rounded())
            return (Double(micros / 2) / 1_000_000, Double(micros * 2 / 3) / 1_000_000)
        }
    }

    private func rounded(_ date: Date, _ direction: MinuteRounding) -> Date {
        switch precision {
        case .wholeSeconds:
            return date.roundedToWholeSecondMinute(direction)
        case .microseconds:
            return date.roundedToMicrosecondMinute(direction)
        }
    }
}
