#!/bin/sh
set -u

if [ $# -ne 0 ]; then
    echo "usage: $0" >&2
    exit 2
fi

if ! xcrun --sdk watchos --show-sdk-path >/dev/null 2>&1; then
    echo "the watchOS SDK is not available; this check needs Xcode" >&2
    exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# SwiftPM generates Bundle.module for a package with resources; swiftc alone needs a stand-in.
cat > "$work/bundle.swift" <<'EOF'
import Foundation

extension Foundation.Bundle {
    static let module = Bundle.main
}
EOF

find "$root/Sources" -name '*.swift' | sort > "$work/sources"
if ! tr '\n' '\0' < "$work/sources" | xargs -0 xcrun --sdk watchos swiftc -target arm64_32-apple-watchos9.0 \
    -module-name Adhan -parse-as-library -O -wmo -emit-ir "$work/bundle.swift" -o "$work/adhan.ll"; then
    echo "FAIL  the module does not compile for arm64_32-apple-watchos9.0"
    exit 1
fi

xcrun swift-demangle --simplified < "$work/adhan.ll" | awk '
/^define / {
    name = $0
    sub(/^define [^@]*@"?/, "", name)
    sub(/"?\(.*/, "", name)
    sub(/^specialized /, "", name)
    sub(/^static /, "", name)
    keep = (name ~ /Malaysia/ || name ~ /^PrayerTimes\.init$/ || name ~ /^one-time initialization function for (map|all|byCode|shared|deltaCells)$/)
}
keep { print name "\t" $0 }
/^}/ { keep = 0 }
' > "$work/path.ll"

grep -E '^(MalaysiaZone\.|MalaysiaZones\.|MalaysiaZoneMap\.(zoneAt|day)\b)' "$work/path.ll" > "$work/coordinate-path.ll"

status=0

absent() {
    if grep -E "$3" "$2" | grep -v -E "$4" > "$work/hits"; then
        echo "FAIL  $1"
        cut -c1-200 "$work/hits" | sed 's/^/      /'
        status=1
    else
        echo "ok    $1"
    fi
}

present() {
    if scope=$2 pattern=$3 awk -F'\t' '$1 ~ ENVIRON["scope"] && $2 ~ ENVIRON["pattern"] { found = 1 } END { exit !found }' "$work/path.ll"; then
        echo "ok    $1"
    else
        echo "FAIL  $1"
        status=1
    fi
}

functions=$(cut -f1 "$work/path.ll" | sort -u | wc -l | tr -d ' ')
echo "arm64_32-apple-watchos9.0, $(grep -c '^define ' "$work/adhan.ll") functions, $functions in the Malaysian lookup scope"
absent "no checked 32-bit multiply on the path, except the minute-to-seconds conversion of user adjustments" "$work/path.ll" 'mul\.with\.overflow\.i32' '^MalaysiaOfficialTimes\.lookup'
absent "no Double converted to a 32-bit integer on the path, except the Hanafi shift in minutes" "$work/path.ll" 'fpto[su]i double [^ ]+ to i32' '^MalaysiaOfficialTimes\.hanafiShift'
absent "no 32-bit checked arithmetic or Double conversion on the coordinate and day-number path" "$work/coordinate-path.ll" '(add|sub|mul)\.with\.overflow\.i32|fpto[su]i double [^ ]+ to i32' '^$'
present "the region minimums start at Int64.max" '^MalaysiaZoneMap\.parse' 'phi i64 \[ 9223372036854775807,'
present "the region maximums start at Int64.min" '^MalaysiaZoneMap\.parse' 'phi i64 \[ -9223372036854775808,'
present "the edge products are 64-bit" '^MalaysiaZoneMap\.zoneAt' 'smul\.with\.overflow\.i64'
present "the coordinates and the margins convert to 64-bit integers" '^MalaysiaZoneMap\.zoneAt' 'fptosi double [^ ]+ to i64'
present "the polyline accumulators are 64-bit" '^MalaysiaZoneMap\.decodePolyline' 'sadd\.with\.overflow\.i64'
present "the day number is 64-bit" '^MalaysiaZone\.' 'mul (nsw )?i64 [^,]+, 10000'

exit $status
