# Adhan Swift

Adhan Swift is a well tested and well documented library for calculating Islamic prayer times.

All astronomical calculations are high precision equations directly from the book _“Astronomical Algorithms” by Jean Meeus_. This book is recommended by the Astronomical Applications Department of the U.S. Naval Observatory and the Earth System Research Laboratory of the National Oceanic and Atmospheric Administration.

Implementations of Adhan in other languages can be found in the parent repo [Adhan](https://github.com/batoulapps/Adhan).

## Installation

### Swift Package Manager

- Project > Package Dependencies
- Add https://github.com/batoulapps/adhan-swift.git
- Select "Up to Next Major" with "1.5.0"

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

To avoid confusion with timezones, the date parameter passed in should be an instance of
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
of `Date` and as such will refer to a fixed point in universal time. To display these
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
let formatter = DateFormatter()
formatter.timeStyle = .medium
formatter.timeZone = TimeZone(identifier: "America/New_York")!

let cal = Calendar(identifier: Calendar.Identifier.gregorian)
let date = cal.dateComponents([.year, .month, .day], from: Date())

let coordinates = Coordinates(latitude: 35.78056, longitude: -78.6389)

var params = CalculationMethod.northAmerica.params
params.madhab = .hanafi

if let prayers = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: params) {
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
