# Adhan Swift

![badge-languages][] ![badge-pms][] ![badge-platforms][]

[![badge-pod][]][cocoapods] [![badge-travis][]][travis] [![badge-cov][]][codecov]

Adhan Swift is a well tested and well documented library for calculating Islamic prayer times. Adhan Swift supports Swift 4.0, Swift 4.2, Swift 5.0 and Objective-C.

All astronomical calculations are high precision equations directly from the book [“Astronomical Algorithms” by Jean Meeus](http://www.willbell.com/math/mc1.htm). This book is recommended by the Astronomical Applications Department of the U.S. Naval Observatory and the Earth System Research Laboratory of the National Oceanic and Atmospheric Administration.

Implementations of Adhan in other languages can be found in the parent repo [Adhan](https://github.com/batoulapps/Adhan).

## Installation

### CocoaPods

For [CocoaPods](https://cocoapods.org/) add the following to your [Podfile](https://guides.cocoapods.org/syntax/podfile.html):

```ruby
pod 'Adhan'
```

### Carthage

For [Carthage](https://github.com/Carthage/Carthage) add the following to your [Cartfile](https://github.com/Carthage/Carthage/blob/master/Documentation/Artifacts.md#cartfile):

```ruby
github "batoulapps/adhan-swift" "main"
```

### Swift Package Manager

For [SPM](https://swift.org/package-manager/) add the following to your `Package.swift` file:

```swift
// swift-tools-version:4.2
dependencies: [
    .package(url: "https://github.com/batoulapps/adhan-swift", from: "1.3.2"),
]
```

### Manually

You can also manually add Adhan.

- Download the source.
- Add Adhan.xcodeproj as a subproject in your app's project.
- Drag Adhan.framework to "Linked Frameworks and Libraries" in your app's target.


## Usage

To get prayer times initialize the `PrayerTimes` struct passing in coordinates,
date, and calculation parameters.

```swift
let prayers = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: params)
```

### Initialization parameters

#### Coordinates

Create a `Coordinates` struct with the latitude and longitude for the location
you want prayer times for.

```swift
let coordinates = Coordinates(latitude: 35.78056, longitude: -78.6389)
```

#### Date

To avoid confusion with timezones the date parameter passed in should be an instance of
`DateComponents`. The year, month, and day components need to be populated. All other
components will be ignored. The year, month and day values should be for the local date
that you want prayer times for. These date components are expected to be for the Gregorian calendar.

```swift
let cal = Calendar(identifier: Calendar.Identifier.gregorian)
let date = cal.dateComponents([.year, .month, .day], from: Date())
```

### Calculation parameters & Calculation Methods

The rest of the needed information is contained within the `CalculationParameters` struct.

[Calculation Parameters & Methods Guide](METHODS.md)



### Prayer Times

Once the `PrayerTimes` struct has been initialized it will contain members
for all five prayer times and the time for sunrise. The prayer times will be instances
of NSDate and as such will refer to a fixed point in universal time. To display these
times for the local timezone you will need to create a date formatter and set
the appropriate timezone.

```swift
let formatter = DateFormatter()
formatter.timeStyle = .medium
formatter.timeZone = TimeZone(identifier: "America/New_York")!

print("fajr \(formatter.string(from: prayers.fajr))")
```

## Full Example

```swift
let cal = Calendar(identifier: Calendar.Identifier.gregorian)
let date = cal.dateComponents([.year, .month, .day], from: Date())
let coordinates = Coordinates(latitude: 35.78056, longitude: -78.6389)
var params = CalculationMethod.moonsightingCommittee.params
params.madhab = .hanafi
if let prayers = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: params) {
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    formatter.timeZone = TimeZone(identifier: "America/New_York")!

    print("fajr \(formatter.string(from: prayers.fajr))")
    print("sunrise \(formatter.string(from: prayers.sunrise))")
    print("dhuhr \(formatter.string(from: prayers.dhuhr))")
    print("asr \(formatter.string(from: prayers.asr))")
    print("maghrib \(formatter.string(from: prayers.maghrib))")
    print("isha \(formatter.string(from: prayers.isha))")
}
```

## Convenience Utilities

The `PrayerTimes` struct has functions for getting the current prayer and the next prayer. You can also get the time for a specified prayer, making it
easier to dynamically show countdowns until the next prayer.

```swift
let prayerTimes = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: params)

let current = prayerTimes.currentPrayer()
let next = prayerTimes.nextPrayer()
let countdown = prayerTimes.time(for: next)
```

## Sunnah Times

The Adhan library can also calulate Sunnah times. Given an instance of `PrayerTimes`, you can get a `SunnahTimes` struct with the times for Qiyam.

```swift
if let sunnahTimes = SunnahTimes(from: todayPrayers) {
	print(dateFormatter.string(from: sunnahTimes.lastThirdOfTheNight)
	print(dateFormatter.string(from: sunnahTimes.middleOfTheNight)
}
```

## Unified London Times

For London, you can use pre-calculated authoritative prayer times instead of astronomical calculations by using the `unifiedLondonTimes` calculation method. This feature uses the London Unified Prayer Timetable data that is embedded in the library (as of version 1.3.1).

### Usage

The London times data is automatically loaded, so you can use the `unifiedLondonTimes` calculation method directly:

```swift
let coordinates = Coordinates(latitude: 51.5074, longitude: -0.1278) // London
let date = DateComponents(year: 2025, month: 1, day: 1)
let params = CalculationMethod.unifiedLondonTimes.params

let prayerTimes = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: params)
```

### With Adjustments

Time adjustments work the same way as with calculated methods:

```swift
var params = CalculationMethod.unifiedLondonTimes.params
params.adjustments.fajr = 5 // Add 5 minutes to Fajr time
params.adjustments.isha = -3 // Subtract 3 minutes from Isha time

let prayerTimes = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: params)
```

### Custom Data (Optional)

If you need to override the embedded data with custom London times, you can still initialize the lookup manually:

```swift
// Load custom JSON string
let customJsonString = """
{
    "city": "london",
    "times": {
        "2025-01-01": {
            "date": "2025-01-01",
            "fajr": "06:26",
            "sunrise": "08:03",
            "dhuhr": "12:09",
            "asr": "13:45",
            "maghrib": "16:04",
            "isha": "17:41"
        }
    }
}
"""

try LondonTimesLookup.initialize(with: customJsonString)
```

### JSON Data Format

The JSON data should follow this structure:

```json
{
    "city": "london",
    "times": {
        "YYYY-MM-DD": {
            "date": "YYYY-MM-DD",
            "fajr": "HH:mm",
            "sunrise": "HH:mm", 
            "dhuhr": "HH:mm",
            "asr": "HH:mm",
            "maghrib": "HH:mm",
            "isha": "HH:mm"
        }
    }
}
```

**Note**: The lookup method will return `nil` if prayer times for the requested date are not available in the JSON data.

## Qibla Direction

Get the direction, in degrees from North, of the Qibla from a given set of coordinates.

```swift
let nyc = Coordinates(latitude: 40.7128, longitude: -74.0059)
let qiblaDirection = Qibla(coordinates: nyc).direction
```

## Contributing

Adhan is made publicly available to provide a well tested and well documented library for Islamic prayer times to all
developers. We accept feature contributions provided that they are properly documented and include the appropriate
unit tests. We are also looking for contributions in the form of unit tests of of prayer times for different
locations, we do ask that the source of the comparison values be properly documented. For all pull requests, 
use `develop` as the base branch.

## License

Adhan is available under the MIT license. See the LICENSE file for more info.

[badge-pod]: https://img.shields.io/cocoapods/v/Adhan.svg?label=version
[badge-pms]: https://img.shields.io/badge/supports-CocoaPods%20%7C%20Carthage%20%7C%20SwiftPM-green.svg
[badge-languages]: https://img.shields.io/badge/languages-Swift%20%7C%20ObjC-orange.svg
[badge-platforms]: https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20watchOS%20%7C%20tvOS-lightgrey.svg
[badge-travis]: https://travis-ci.org/batoulapps/adhan-swift.svg?branch=master
[badge-cov]: https://codecov.io/gh/batoulapps/adhan-swift/branch/master/graph/badge.svg
[travis]: https://travis-ci.org/batoulapps/adhan-swift
[cocoapods]: https://cocoapods.org/pods/Adhan
[codecov]: https://codecov.io/gh/batoulapps/adhan-swift
