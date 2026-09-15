import Foundation

/// Fajr fallback used only when the raw 18-degree dawn is absent in the Northern Hemisphere.
public enum WifaqulFajrRule: String, Codable, Equatable, Sendable {
    /// Rebase the most recent valid dawn's UTC time onto the requested date.
    case aqrabulAyyam
    /// Midpoint between yesterday's raw sunset and today's sunrise.
    case nisfAlLayl
}

/// Northern Isha hardship policy; absent twilight always uses the longest-day reference.
public enum WifaqulIshaRule: String, Codable, Equatable, Sendable {
    case longestDay
    case seventhOfNight
}

/// Pillars' explicit selection of published Wifaqul variants, not current app parity.
/// See https://www.wifaqululama.co.uk/salahtimes/ and https://www.wifaqululama.co.uk/highlat/.
public struct WifaqulOptions: Codable, Equatable, Sendable {
    public let fajrRule: WifaqulFajrRule
    public let ishaRule: WifaqulIshaRule

    /// Creates the selected profile. Generic high-latitude rules are ignored by Wifaqul.
    public init(fajrRule: WifaqulFajrRule = .aqrabulAyyam, ishaRule: WifaqulIshaRule = .longestDay) {
        self.fajrRule = fajrRule
        self.ishaRule = ishaRule
    }
}
