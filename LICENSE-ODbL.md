# Licence of the Malaysian zone map

The zone map is derived from OpenStreetMap data and is offered under the
[Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/)
(ODbL). © OpenStreetMap contributors, https://www.openstreetmap.org/copyright.

This repository holds one file with OpenStreetMap-derived data:

- `Sources/Resources/malaysia_zones.txt`, the zone map

It is a byte-for-byte copy of `data/malaysia/malaysia_zones.txt` in
[PillarsApp/adhan-dart](https://github.com/PillarsApp/adhan-dart), where its
`LICENSE-ODbL.md` also lists the build inputs that stay in that repository.

The zone map also contains district boundaries from geoBoundaries gbOpen MYS
ADM2 (CC BY 3.0, sources geoBoundaries and citypopulation.de) and centre points
from GeoNames (CC BY 4.0). Keep this file, and the credits in `README.md`, with
any copy of the file above.

The library code stays under the MIT licence in `LICENSE`. The prayer
timetables in `Sources/Resources/malaysia_times.txt` are published by JAKIM and
the Selangor State Mufti Department and are not covered by this file.
`Sources/Resources/MALAYSIA_MANIFEST` records where the data came from and holds
no map data.
