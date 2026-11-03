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
  run, rejects an Asr angle the sun does not reach that day, and treats a
  day whose times come out of order, or less than five minutes apart, as
  one whose times can't be computed. This is the default value.

  **singlePass**

  Applies the hour angle correction once and keeps every time it produces,
  as version 1.4.0 did. On summer days above about 48.5° latitude Isha
  differs from `iterative`, by up to 4 minutes at London's latitude and by
  up to about 40 minutes at Reykjavik's. Combined
  with `polarCircleResolution` set to `unresolved`, polar days behave as
  they did in 1.4.0 too. Fixes outside the correction, such as the one for
  longitudes near ±180°, apply under both values.
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
}
