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
| rounding | The behavior for rounding prayer times. Either to nearest minute, to the higher minute, none, or `startsUpSunriseDown`, which rounds sunrise down and every other time, sunnah times included, up to the next minute whenever any part of a minute is past it.  |
| shafaq | Used by the MoonsightingCommittee method to determine how to calculate Isha. See explanation of values below. |
| polarCircleResolution | Which setting from the PolarCircleResolution enum to use for resolving prayer times inside the polar circles. Default value is `aqrabBalad`. |
| hourAngleCorrection | Which setting from the HourAngleCorrection enum to use when correcting the time the sun reaches each prayer's angle. Default value is `iterative`. |
| malaysiaZone | The code of the official Malaysian zone to read, such as `WLY01`, when the method is `malaysiaOfficial`. Default value is nil, which resolves the zone from the coordinates. |

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
| unifiedLondonTimes | Unified London Prayer Times. Uses pre-calculated prayer times for London from embedded JSON data. No astronomical calculations are performed. |
| malaysiaOfficial | Official Malaysian timetable published by JAKIM and the state muftis, read per prayer zone from embedded data. Where no row covers the zone and date, calculates with Fajr angle 18°, Isha angle 18° and the offsets Fajr +1, Sunrise −1, Dhuhr +3, Asr +1, Maghrib +2, Isha +1. |

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

## PolarCircleResolution

Strategy used to resolve prayer times for locations inside the polar circles, where the sun may not rise or set, or may not reach the angle required for a given prayer, on certain days of the year.

| Value | Description |
| ----- | ----------- |
| aqrabBalad | (default) Finds the closest location (moving toward the equator at the same longitude) for which prayer times can be computed. |
| aqrabYaum | Finds the closest date (forward or backward) for which prayer times can be computed. |
| unresolved | Leaves prayer times unresolved, `PrayerTimes` initialization returns nil when they can't be computed. See [README](README.md#polar-circle-locations). |

## HourAngleCorrection

How the time at which the sun reaches a given altitude (sunrise, sunset, Fajr, Isha and Asr) is corrected, and how strictly the resulting times are validated.

| Value | Description |
| ----- | ----------- |
| iterative | (default) Repeats the hour angle correction until it converges or ten passes have run, rejects an Asr angle the sun does not reach that day, treats a day whose times come out of order, or less than five minutes apart, as one whose times can't be computed, and at longitudes near ±180° picks the solar transit nearest the longitude's mean noon, so consecutive days never jump by a day. |
| singlePass | Applies the hour angle correction once and keeps every time it produces, as version 1.4.0 did. Measured for 2026 with `highLatitudeRule` set to `middleOfTheNight`, the two values differ by 4 minutes for Isha at London (16 July), 41 minutes for ISNA Isha at Reykjavik (25 August) and 43 minutes for Isha at Edmonton with 18° angles (13 May). With `highLatitudeRule` nil, which means `seventhOfTheNight` above 48°, those three places do not differ on any day of 2026. At Tromso the two values differ by 50 minutes for Asr (21 January) and 116 minutes for Moonsighting Committee Fajr (17 May), with or without the rule. With `polarCircleResolution` set to `unresolved`, polar days behave as they did in 1.4.0 too. `singlePass` also keeps 1.4.0's choice of day near ±180°, where on some days, at Suva or the Chatham Islands for example, its times fall a day apart from those `iterative` returns. Two changes since 1.4.0 apply under both values: with `highLatitudeRule` nil, latitudes south of 48°S get the same rule as those north of 48°N, and `SunnahTimes` honours `rounding`. |

#### Shafaq

Shafaq is used by the MoonsightingCommittee method to determine what type of twilight to use in order to determine the time for Isha.

| Value | Description |
| ----- | ----------- |
| general | General is a combination of Ahmer and Abyad. This is the defualt value and will provide more reasonable times for locations at higher latitudes. |
| ahmer | Ahmer means the twilight is the red glow in the sky. Used by the Shafi, Maliki, and Hanbali madhabs. This generally produces an earlier Isha time. |
| abyad | Abyad means the twilight is the white glow in the sky. Used by the Hanafi madhab. This generally produces a later Isha time. |
