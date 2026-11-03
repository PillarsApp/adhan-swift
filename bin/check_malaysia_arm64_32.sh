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
    keep = (name ~ /^MalaysiaZone(Map|s)?\./)
}
keep { print name "\t" $0 }
/^}/ { keep = 0 }
' > "$work/zone-map.ll"

status=0

absent() {
    if grep -E "$2" "$work/zone-map.ll" > "$work/hits"; then
        echo "FAIL  $1"
        cut -c1-200 "$work/hits" | sed 's/^/      /'
        status=1
    else
        echo "ok    $1"
    fi
}

present() {
    if scope=$2 pattern=$3 awk -F'\t' '$1 ~ ENVIRON["scope"] && $2 ~ ENVIRON["pattern"] { found = 1 } END { exit !found }' "$work/zone-map.ll"; then
        echo "ok    $1"
    else
        echo "FAIL  $1"
        status=1
    fi
}

echo "arm64_32-apple-watchos9.0, $(grep -c '^define ' "$work/adhan.ll") functions, $(cut -f1 "$work/zone-map.ll" | sort -u | wc -l | tr -d ' ') in the zone map and the zone catalog"
absent "no checked 32-bit multiply" 'mul\.with\.overflow\.i32'
absent "no Double converted to a 32-bit integer" 'fpto[su]i double [^ ]+ to i32'
present "the region minimums start at Int64.max" '^MalaysiaZoneMap\.parse' 'phi i64 \[ 9223372036854775807,'
present "the region maximums start at Int64.min" '^MalaysiaZoneMap\.parse' 'phi i64 \[ -9223372036854775808,'
present "the edge products are 64-bit" '^MalaysiaZoneMap\.zoneAt' 'smul\.with\.overflow\.i64'
present "the coordinates and the margins convert to 64-bit integers" '^MalaysiaZoneMap\.zoneAt' 'fptosi double [^ ]+ to i64'
present "the day number is 64-bit" '^MalaysiaZone\.' 'mul (nsw )?i64 [^,]+, 10000'

exit $status
