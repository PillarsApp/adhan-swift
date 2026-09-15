# Calculation Parameters Guide

## Calculation parameters

To calculate Prayer Times, a CalculatonParameters struct is required.
Instead of manually initializing this struct it is recommended to use one of the pre-populated
instances by calling the `params` var on the `CalculationMethod` enum. You can then further
customize the calculation parameters if needed.

```swift
var params = CalculationMethod.moonsightingCommittee.params
params.madhab = .hanafi
params.adjustments.fajr = 2
```

| Parameter | Description |
| --------- | ----------- |
| method    | Which preset from the CalculationMethod enum was used. Default value is `other`. |
| fajrAngle | Angle of the sun below the horizon used to calculate Fajr. |
| maghribAngle | Angle of the sun below the horizon used to calculate Maghrib, used for some Calculation Methods. |
| ishaAngle | Angle of the sun below the horizon used to calculate Isha. |
| ishaInterval | Minutes after Maghrib (if set, the time for Isha will be Maghrib plus ishaInterval). |
| madhab | Which setting from the Madhab enum to use for calculating Asr. |
| highLatitudeRule | Which setting from the HighLatitudeRule enum to use for calculating the minimum time for Fajr and the maximum time for Isha. |
| adjustments | PrayerAdjustments struct with custom prayer time adjustments in minutes for each prayer time. |
| rounding | The behavior for rounding prayer times. Either to nearest minute, to the higher minute, or none.  |
| shafaq | Used by the MoonsightingCommittee method to determine how to calculate Isha. See explanation of values below. |
| wifaqulOptions | Optional WifaqulOptions for wifaqulUlama only; nil uses the defaults below. Legacy encoded parameters without this field still decode. |

## CalculationMethod

Preset calculation parameters for different regions.

| Value | Description |
| ----- | ----------- |
| muslimWorldLeague | Muslim World League. Standard Fajr time with an angle of 18°. Earlier Isha time with an angle of 17°. |
| egyptian | Egyptian General Authority of Survey. Early Fajr time using an angle 19.5° and a slightly earlier Isha time using an angle of 17.5°. |
| karachi | University of Islamic Sciences, Karachi. A generally applicable method that uses standard Fajr and Isha angles of 18°. |
| ummAlQura | Umm al-Qura University, Makkah. Uses a fixed interval of 90 minutes from maghrib to calculate Isha. And a slightly earlier Fajr time with an angle of 18.5°. *Note: you should add a +30 minute custom adjustment for Isha during Ramadan.* |
| dubai | Used in the UAE. Slightly earlier Fajr time and slightly later Isha time with angles of 18.2° for Fajr and Isha in addition to 3 minute offsets for sunrise, Dhuhr, Asr, and Maghrib. |
| qatar | Same Isha interval as `ummAlQura` but with the standard Fajr time using an angle of 18°. |
| kuwait | Standard Fajr time with an angle of 18°. Slightly earlier Isha time with an angle of 17.5°. |
| moonsightingCommittee | Method developed by Khalid Shaukat, founder of Moonsighting Committee Worldwide. Uses standard 18° angles for Fajr and Isha in addition to seasonal adjustment values. This method automatically applies the 1/7 approximation rule for locations at or above 55° latitude. Recommended for North America and the UK. |
| singapore | Used in Singapore, Malaysia, and Indonesia. Early Fajr time with an angle of 20° and standard Isha time with an angle of 18°. |
| turkey | An approximation of the Diyanet method used in Turkey. This approximation is less accurate outside the region of Turkey. |
| tehran | Institute of Geophysics, University of Tehran. Early Isha time with an angle of 14°. Slightly later Fajr time with an angle of 17.7°. Calculates Maghrib based on the sun reaching an angle of 4.5° below the horizon. |
| northAmerica | Also known as the ISNA method. Can be used for North America, but the moonsightingCommittee method is preferable. Gives later Fajr times and early Isha times with angles of 15°. |
| other | Defaults to angles of 0°, should generally be used for making a custom method and setting your own values. |
| wifaqulUlama | Pillars-selected Wifaqul profile: Fajr 18°, last-valid-day Aqrab, northern Isha hardship cap, Dhuhr +4 minutes and Maghrib +5 minutes. |

## Wifaqul Ulama — selected profile, version 1

This is a Pillars fork extension, not a claim of exact agreement with the Wifaqul store app.
The [18-degree explanation](https://www.wifaqululama.co.uk/18degrees/),
[FAQ](https://www.wifaqululama.co.uk/salahtimes/), and
[high-latitude guidance](https://www.wifaqululama.co.uk/highlat/) describe multiple variants.
This profile chooses last-valid-day Aqrabul Ayyam, rather than the FAQ's historical averaging;
Wifaqul's [Android 10.4.0 release](https://github.com/wifaqululama/android_public_release_mirror/releases/tag/10.4.0)
also describes changing Aqrab to the last actual Fajr.

```swift
var params = CalculationMethod.wifaqulUlama.params
params.madhab = .hanafi // Omit to keep the Shafi default.
let prayers = PrayerTimes(
    coordinates: Coordinates(latitude: 51.5074, longitude: -0.1278),
    date: DateComponents(year: 2026, month: 6, day: 21),
    calculationParameters: params
)
```

The fixed policy is:

- Fajr uses the actual 18° dawn whenever it exists. When absent in the northern hemisphere,
  reuse the last valid raw dawn's offset from UTC midnight throughout that missing-twilight
  interval. Reference searches are bounded to 370 days in each direction; there is no averaging.
- Isha uses 15° at latitude **48° north or higher**, including exactly 48°, and 18° below it.
  The inclusive boundary is an explicit choice because the FAQ overlaps at equality.
- At 48° north or higher, default Isha is the earlier of actual 15° twilight and the annual
  longest-day sunset plus 65 minutes; when twilight is absent, use that annual cap.
  The reference is the greatest raw sunrise-to-sunset duration among June 15–25 of the requested
  year, with the earliest day winning a tie. Its sunset offset is rebased onto the requested
  UTC date. This is **not today's sunset plus 65 minutes**, nor a fixed civil-clock cap.
- Dhuhr adds four minutes to transit, Maghrib adds five minutes to raw sunset, and sunrise has
  no method adjustment. Both Asr madhabs are supported. User and method adjustments are applied
  once after policy selection, followed by the existing rounding setting.
- Generic `highLatitudeRule` is ignored for this method. Its angles must remain 18°/18° in
  the parameter object, with zero Isha interval and no Maghrib angle; the effective northern
  Isha angle is selected internally without mutating reusable parameters.

Optional alternatives are explicit:

```swift
params.wifaqulOptions = WifaqulOptions(
    fajrRule: .nisfAlLayl,
    ishaRule: .seventhOfNight
)
```

Nisf replaces only missing Fajr with the midpoint from **previous raw sunset to today's
sunrise**. Seventh-of-night caps existing northern Isha at one seventh of the interval from
**today's raw sunset to tomorrow's sunrise**; absent Isha still uses the annual longest-day
cap. Defaults are `.aqrabulAyyam` and `.longestDay`. Options are immutable, `Codable`,
`Equatable`, and `Sendable`; absent options in older encoded parameters select these defaults.

Missing required horizon/reference events, missing southern twilight, or incompatible custom
angles make `PrayerTimes` return `nil`; no substitute latitude is used. This is not a
southern-hemisphere summer policy. Reference caches use exact coordinates and year, hold
at most 32 entries, and are synchronized for concurrent callers. Other calculation methods
and their encoded names are unchanged.

Tests include 47 independent Astronomy Engine 2.1.19 reference cases with a two-minute
cross-model tolerance, complete seasonal transitions, travel timezones, date-line rollover,
both madhabs, options, adjustments, serialization, and concurrent/cache-eviction behavior.
Expected instants are not generated by either Adhan implementation. Their provenance is in
`Tests/Resources/wifaqul-astronomy-engine.json`; `tools/generate_wifaqul_fixtures.cjs` reproduces them.

## Madhab

Rule for calculating the time for Asr.

| Value | Description |
| ----- | ----------- |
| shafi | Earlier Asr time (use for Shafi, Maliki, Hanbali, and Jafari). |
| hanafi | Later Asr time. |

## HighLatitudeRule

Rule for approximating Fajr and Isha at high latitudes.

| Value | Description |
| ----- | ----------- |
| middleOfTheNight | Fajr won't be earlier than the midpoint of the night and isha won't be later than the midpoint of the night. This is the default value to prevent fajr and isha crossing boundaries. |
| seventhOfTheNight | Fajr will never be earlier than the beginning of the last seventh of the night and Isha will never be later than the end of the first seventh of the night. This is recommended to use for locations above 48° latitude to prevent prayer times that would be difficult to perform. |
| twilightAngle | The night is divided into portions of roughly 1/3. The exact value is derived by dividing the fajr/isha angles by 60. This can be used to prevent difficult fajr and isha times at certain locations. |

You can get the recommended High Latitude Rule for a location by calling the `recommended(for:)` function and passing in the coordinates for the location.

```
let myCoordinates = Coordinates(latitude: 48.983226, longitude: -3.216649)
let highLatRule = HighLatitudeRule.recommended(for: myCoordinates)
```

#### Shafaq

Shafaq is used by the MoonsightingCommittee method to determine what type of twilight to use in order to determine the time for Isha.

| Value | Description |
| ----- | ----------- |
| general | General is a combination of Ahmer and Abyad. This is the defualt value and will provide more reasonable times for locations at higher latitudes. |
| ahmer | Ahmer means the twilight is the red glow in the sky. Used by the Shafi, Maliki, and Hanbali madhabs. This generally produces an earlier Isha time. |
| abyad | Abyad means the twilight is the white glow in the sky. Used by the Hanafi madhab. This generally produces a later Isha time. |
