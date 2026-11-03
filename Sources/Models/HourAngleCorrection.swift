//
//  HourAngleCorrection.swift
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

import Foundation

/**
  How the time at which the sun reaches a given altitude (sunrise, sunset,
  Fajr, Isha and Asr) is corrected, and how strictly the resulting times
  are validated.

  *Values*

  **iterative**

  Repeats the hour angle correction until it converges or ten passes have
  run, rejects an Asr angle the sun does not reach that day, treats a day
  whose times come out of order, or less than five minutes apart, as one
  whose times can't be computed, and at longitudes near ±180° picks the
  solar transit nearest the longitude's mean noon, so the times of
  consecutive days never jump by a day. This is the default value.

  **singlePass**

  Applies the hour angle correction once and keeps every time it produces,
  as version 1.4.0 did. The two values differ most where the sun's altitude
  changes slowly. Measured for 2026 with `highLatitudeRule` set to
  `middleOfTheNight`: Isha at London differs by 4 minutes on 16 July, Isha
  at Reykjavik (ISNA) by 41 minutes on 25 August, and Isha at Edmonton with
  18° angles by 43 minutes on 13 May. With `highLatitudeRule` nil, which
  means `seventhOfTheNight` above 48°, those three places do not differ on
  any day of 2026. At Tromso Asr differs by 50 minutes on 21 January and
  Moonsighting Committee Fajr by 116 minutes on 17 May, with or without the
  rule. Combined with `polarCircleResolution` set to
  `unresolved`, polar days behave as they did in 1.4.0 too. With the default
  `aqrabBalad`, a polar day can return times out of order, because
  `singlePass` skips the ordering check and `aqrabBalad` substitutes a
  latitude.

  `singlePass` also keeps 1.4.0's choice of day at longitudes near ±180°.
  On some days there, at Suva or the Chatham Islands for example, its times
  fall a day apart from those `iterative` returns. Choose `singlePass` when
  the times must agree with another system that still runs 1.4.0 or a port
  of it.

  Two changes since 1.4.0 apply under both values: with `highLatitudeRule`
  nil, latitudes south of 48°S now get the same rule as those north of
  48°N, and `SunnahTimes` now honours `rounding`.
 */
public enum HourAngleCorrection: String, Codable, CaseIterable {
    case iterative
    case singlePass
}

extension HourAngleCorrection {
    var maximumIterations: Int {
        switch self {
        case .iterative:
            return 10
        case .singlePass:
            return 1
        }
    }

    var validatesTimes: Bool {
        switch self {
        case .iterative:
            return true
        case .singlePass:
            return false
        }
    }

    var anchorsTransitToLongitude: Bool {
        switch self {
        case .iterative:
            return true
        case .singlePass:
            return false
        }
    }
}
