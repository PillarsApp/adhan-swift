# Changelog

## 2.4.0

- Add `Rounding.startsUpSunriseDown`, which keeps each computed time to the microsecond, rounds sunrise down to its minute, and rounds every other time, sunnah times included, up to the next minute when any part of a minute is past it. It gives the same minutes as `Rounding.startsUpSunriseDown` in adhan-dart 3.1.0, which `Tests/Resources/rounding/vectors.json` pins. `nearest`, `up` and `none` keep their output and their raw values, which `Tests/Resources/rounding/golden_1a1b6e7.tsv` pins over every method, fourteen cities and every day of 2026.

## 2.3.0

- `PublishedTimetable` loads a published prayer timetable in the `OTT 1` format at runtime from `Data`, with the header checked on `init` and each locality-year decoded on first use. `validateAllRows()` checks every cell once. A malformed file throws `FormatError`, whose `rule` is the `PublishedRule` the bytes break.
- `OfficialTimetableSource` is the interface for published times, with `lookup` returning `OfficialLookup`: `.published(row)`, `.noLocality` or `.noRow(locality)`. `PublishedTimetable` and `MalaysiaTimetable.source` implement it.
- `PrayerTimes(official:parameters:adjustments:)` assembles six times from an `OfficialRow`, applying the Hanafi Asr rule at the locality's reference point and the user adjustments. It returns nil only when the file has no `asrHanafi` column and the sun does not reach one of the two shadow lengths there that day, or an hour or the difference in minutes does not fit in 32 bits, which can happen very near a pole; a polar day with no sunrise or sunset still gets an Asr. `PrayerTimes.officialRow` exposes the row.
- `CalculationMethod.malaysiaOfficial` reads its rows through `MalaysiaTimetable.source` and the same assembly. Its times are unchanged, proven by a golden over every zone, every day of 2026 and 2027, both madhabs, three adjustment sets and both zone modes.
- `MalaysiaTimetable.day(_:on:)` returns nil for a date that is not a calendar day, such as 30 February. Earlier releases returned the row of the normalized date. `PrayerTimes.init?` already returns nil for the same input.
- `Coordinates` is `Sendable`.
- Unless a `file.*` rule applies first, a header line that is not UTF-8 or does not parse as one JSON object reports `header.json`, here and in the Dart library. A repeated key together with a nesting, surrogate or number fault reports the same rule in both libraries.
- The two libraries do not report the same rule on every malformed file. A file that breaks two or more rules can report a different one of them, which the format allows. A key missing inside a zone, locality, `point` or `area` reports `header.keyAbsent` here and the rule of that field in Dart. A number where an offset date or a polygon goes reports `zone.offset.shape` or `locality.area.polygons` here and `zone.offset.date` or `locality.area.polyline` in Dart. A number written with very many digits is judged here by the value it denotes, as the format says, and Dart's `jsonDecode` can misjudge it.
- `bin/check_published_arm64_32.sh` compiles the module for watchOS `arm64_32` and checks the published decoder and lookup for 32-bit overflow risks, as `bin/check_malaysia_arm64_32.sh` does for the Malaysian lookup.

Earlier releases have no changelog entry. See the git tags.
