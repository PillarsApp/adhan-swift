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

#### Polar circle locations

Near the polar circles (latitudes beyond ±66.56°) the sun may not rise or
set, or may not reach the angle required for a given prayer, on certain days
of the year. By default, the `polarCircleResolution` calculation parameter is
set to `aqrabBalad`, which automatically substitutes the closest latitude
(at the same longitude) for which prayer times can be computed, so this is
handled for you in almost every case.

It's still possible, though rare, for a substitute to not be found (or if
you've set `polarCircleResolution` to `unresolved` yourself), in which case
`PrayerTimes` cannot compute that day's times and initialization returns nil.

See [`polarCircleResolution`](METHODS.md#polarcircleresolution) for the other
available resolution strategies.

#### Keeping the times of version 1.4.0

Versions after 1.4.0 correct the time at which the sun reaches each prayer's
angle iteratively, validate that the times come out in order, and at longitudes
near ±180° pick the solar transit nearest the longitude's mean noon, so consecutive
days never jump by a day. The times move most where
the sun's altitude changes slowly. Measured for 2026 with `highLatitudeRule` set to
`middleOfTheNight`: Isha at London moves 4 minutes on 16 July, Isha at Reykjavik
(ISNA) 41 minutes on 25 August, and Isha at Edmonton with 18° angles 43 minutes
on 13 May. With `highLatitudeRule` left nil, which means `seventhOfTheNight`
above 48°, those three places do not move on any day of 2026. Asr at Tromso
moves 50 minutes on 21 January and Moonsighting Committee Fajr 116 minutes on
17 May, with or without the rule. With
`polarCircleResolution` set to `unresolved`, some polar days that produced times
now return nil. To keep the times version 1.4.0 computed, set the
`hourAngleCorrection` calculation parameter to `singlePass` and
`polarCircleResolution` to `unresolved`. `singlePass` also keeps 1.4.0's choice
of day near ±180°, where on some days, at Suva or the Chatham Islands for
example, its times fall a day apart from those `iterative` returns.

Two changes since 1.4.0 apply under both values: with `highLatitudeRule` nil,
latitudes south of 48°S now get the same rule as those north of 48°N, and
`SunnahTimes` now honours `rounding`.

With `singlePass` and the default `polarCircleResolution` of `aqrabBalad`, a
polar day can return times out of order, because `singlePass` skips the
ordering check and `aqrabBalad` substitutes a latitude.

See [`hourAngleCorrection`](METHODS.md#houranglecorrection).

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

`SunnahTimes` internally computes a second `PrayerTimes` for the following
day (using the same coordinates and calculation parameters) to determine the
length of the night. That computation can fail independently of the
`PrayerTimes` you passed in - near the polar circle, today's times may be
computable while tomorrow's aren't - so `SunnahTimes` initialization can
return nil even when the `PrayerTimes` you passed in is valid.

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

## Official Malaysian Timetable

The library embeds the prayer timetables that JAKIM publishes through e-Solat, the Selangor district timetables from 2027, and a map of the prayer zones. `CalculationMethod.malaysiaOfficial` reads the published row for the zone and date:

```swift
let params = CalculationMethod.malaysiaOfficial.params
let times = PrayerTimes(coordinates: Coordinates(latitude: 3.1390, longitude: 101.6869),
                        date: DateComponents(year: 2026, month: 11, day: 2),
                        calculationParameters: params)!

times.fajr                 // 05:48 at UTC+8, the published Subuh for zone WLY01
times.source               // PrayerTimesSource.official
times.malaysiaZone!.code   // WLY01, resolved from the coordinates
times.malaysiaDay!.imsak   // 05:38; the row also carries Dhuha
```

The zone comes from the coordinates unless `params.malaysiaZone` names one, such as `"WLY02"`. Times are instants built at UTC+8, so the host time zone never changes a result; format them with a `DateFormatter` set to `Asia/Kuala_Lumpur`. User `adjustments` apply on top of the published row. With `Madhab.hanafi`, Asr is the published Asr plus the calculated difference between the Hanafi and Shafi Asr at the zone's reference point.

When no zone covers the coordinates, or the data has no row for the zone and date, `PrayerTimes` calculates instead and `source` says why: `calculatedNoZone` or `calculatedNoRow`. The zone catalog is available through `MalaysiaZones.resolve(_:on:)`, `MalaysiaZones.on(_:)` and `MalaysiaZones.zone(_:)`; a retired zone lists its `successors`. District polygons run past the country border in places and a point within 500 metres of a district snaps to it, so a point up to 3.0 km outside Malaysia's land borders can resolve to a zone. A caller that cares should also check the country. `MalaysiaTimetable.revision` names the embedded data. See the Dart library's [docs/MALAYSIA_TIMES_MAINTENANCE.md](https://github.com/PillarsApp/adhan-dart/blob/master/docs/MALAYSIA_TIMES_MAINTENANCE.md) for the sources, the formats, the yearly update and the notes for the public API; `bin/check_malaysia_data.sh` checks a copied data release against its manifest. `bin/check_malaysia_arm64_32.sh` compiles the module for watchOS `arm64_32`, where `Int` is 32 bits, and fails if the Malaysian lookup gains a 32-bit checked multiply or a Double conversion to 32 bits, or any 32-bit checked arithmetic on the coordinate and day-number path. The scope covers the shared cell codec, the functions nested inside it, and the official assembly in `PrayerTimes`, where the minutes of each user adjustment become seconds through a Double, so no multiply is exempt. It allows the one Double conversion in `PrayerTimes.hanafiShiftMinutes`, and requires it to be the only one in that function. It does not check additions or subtractions elsewhere, and it does not see a checked multiply by a power of two, which the compiler emits as a range check and a shift. It needs Xcode's watchOS SDK, and CI runs it on every pull request into `main`.

Data sources and credits:

- Prayer timetables: JAKIM e-Solat ([www.e-solat.gov.my](https://www.e-solat.gov.my)) and, for the Selangor districts from 2027, the Selangor State Mufti Department ([www.muftiselangor.gov.my](https://www.muftiselangor.gov.my/takwim-solat/)).
- State boundaries: [OpenStreetMap](https://www.openstreetmap.org/copyright), © OpenStreetMap contributors, from the Dart library's pinned snapshot of the `admin_level=4` relations as they stood at 2026-11-04T00:00:00Z. Every border between states, the Putrajaya ring, the Melaka exclave at Tanjung Tuan and the Pahang island Pulau Aceh come from it. The Dart build checks the map against the outlines of OpenStreetMap buildings and places near the state lines, filtered from the Geofabrik extract of 2026-11-03.
- District boundaries inside each state: [geoBoundaries](https://www.geoboundaries.org) gbOpen MYS ADM2 (sources: geoBoundaries, citypopulation.de), licensed under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Runfola, D. et al. (2020) geoBoundaries: A global database of political administrative boundaries. PLoS ONE 15(4): e0231866. The centres of 20 of the islands were measured on the geoBoundaries ADM0 layer, which geoBoundaries records as a 2017 OpenStreetMap export (Wambacher) under the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/). The polygons are simplified to 100 metres, or 80 metres on state borders between zones whose times differ by 2 minutes or more, and quantized to 1e-5 degrees. On state borders the build keeps a raw vertex wherever simplification would move a sampled point of a nearby OpenStreetMap building or place across the line; outlines are sampled every 5 metres, and a `place` area at its centre.
- Zone map: derived from OpenStreetMap data, © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors, licensed under the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/). `LICENSE-ODbL.md` names the file that holds it.
- Place coordinates for the zone test fixtures, the zone reference points, and the centres of the special areas and of the other 17 islands: [GeoNames](https://www.geonames.org), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

## Published Timetables

`PublishedTimetable` reads a prayer timetable an authority publishes, in the `OTT 1` text format the Dart library documents in [docs/PUBLISHED_TIMETABLE_FORMAT.md](https://github.com/PillarsApp/adhan-dart/blob/master/docs/PUBLISHED_TIMETABLE_FORMAT.md). The caller supplies the bytes; the library never touches the file system or the network, and it never verifies a hash, so check the bytes before handing them over. The timetable keeps the `Data` it was given and decodes each row line on first use, so a memory-mapped file must not change while an instance reads it; copy the bytes, or write a replacement under a new name and never rewrite a mapped file in place.

```swift
let data = try Data(contentsOf: url)
let timetable = try PublishedTimetable(data: data)
try timetable.validateAllRows()

let riyadh = Coordinates(latitude: 24.7136, longitude: 46.6753)
switch try timetable.lookup(riyadh, on: DateComponents(year: 2026, month: 1, day: 1)) {
case .published(let row):
    let times = PrayerTimes(official: row, parameters: CalculationMethod.ummAlQura.params)!
    times.fajr                       // the published Fajr as a UTC instant
    times.source                     // PrayerTimesSource.official
    row.locality.name("en")          // Riyadh
    row.published(.imsak)            // nil unless the authority publishes it
case .noLocality:
    break                            // no locality covers the coordinates on that date
case .noRow(let locality):
    break                            // the locality is known but has no row for that date
}
```

`init(data:)` checks the header and the shape of every row line and throws `PublishedTimetable.FormatError` on a malformed file; its `rule` is the `PublishedRule` the bytes break, whose raw value is the rule id in the format doc. Rows decode on first use, so a short-lived process pays for one locality-year, not the whole file. `validateAllRows()` decodes every row once and throws on a bad cell; run it once before trusting a new file. On a file that was never validated, `lookup` throws `FormatError` when the line it reaches is malformed, and the line is not decoded again. Instants come from the published minutes and the offsets inside the file, never from the device time zone, so every platform gives the same `Date` for the same bytes. The test vectors under `Tests/Resources/published/` are shared with the Dart library.

`lookup(_:on:localityId:)` resolves the locality from the coordinates (the nearest point locality whose radius contains them, else the first area locality that contains them within its tolerance) unless `localityId` names one. A date that is not a calendar day, or a coordinate outside its range or not finite, is a caller error and throws `OfficialLookupError`. When the user's madhab has a different shadow factor from the file's `asrShadow`, Asr is the published Asr plus the calculated difference between the two Asr times at the locality's reference point, or the published `asrHanafi` column when the file has one and the user is Hanafi; `PrayerTimes(official:)` returns nil only when the file has no `asrHanafi` column and that difference is undefined, because the sun does not reach one of the two shadow lengths at the reference point on that day, or because an hour or the difference in minutes does not fit in 32 bits, which can happen very near a pole. A polar day with no sunrise or sunset still has an Asr when the sun reaches both. User `adjustments` apply after that; `methodAdjustments` and `rounding` do not apply to published minutes.

`OfficialTimetableSource` is the interface `PublishedTimetable` implements. `MalaysiaTimetable.source` is the same interface over the embedded Malaysian data, and `CalculationMethod.malaysiaOfficial` reads through it. `bin/check_published_arm64_32.sh` compiles the module for watchOS `arm64_32` and fails if the published decoder or lookup gains a 32-bit checked multiply, a wrapping 32-bit multiply, a Double conversion to 32 bits in a function that can trap, or a 64-bit value narrowed to 32 bits behind a trap instead of a range check, with the same limits as the Malaysian check.

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
