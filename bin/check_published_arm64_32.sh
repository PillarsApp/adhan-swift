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
    sub(/^define [^@]*@/, "", name)
    if (substr(name, 1, 1) == "\"") {
        name = substr(name, 2)
        sub(/"\(.*/, "", name)
    } else {
        sub(/\(.*/, "", name)
    }
    sub(/^specialized /, "", name)
    sub(/^static /, "", name)
    keep = (name ~ /Published|HeaderJSON\.|OfficialRow|OfficialLookup|OfficialTimetableSource|Locality|DeltaCellsCodec|CivilDay|^SolarDay\.|^DateComponents\.settingHour\(/ || name ~ /^PrayerTimes\.(init|assembleOfficial|officialAsr|hanafiShiftMinutes|shiftMinutes)\(/)
}
keep { print name "\t" $0 }
/^}/ { keep = 0 }
' > "$work/path.ll"

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
echo "arm64_32-apple-watchos9.0, $(grep -c '^define ' "$work/adhan.ll") functions, $functions in the published lookup scope"
if [ "$functions" -lt 20 ]; then
    echo "FAIL  the published lookup scope matched only $functions functions; the scope pattern is stale"
    status=1
fi
absent "no checked 32-bit multiply on the published path" "$work/path.ll" 'mul\.with\.overflow\.i32' '^$'
awk -F'\t' '
$2 ~ /fpto[su]i double [^ ]+ to i32/ { converts[$1] = 1 }
$2 ~ /llvm\.trap/ { traps[$1] = 1 }
END { for (name in converts) if (name in traps) print name }
' "$work/path.ll" > "$work/hits"
if [ -s "$work/hits" ]; then
    echo "FAIL  no function on the published path both converts a Double to 32 bits and can trap"
    cut -c1-200 "$work/hits" | sed 's/^/      /'
    status=1
else
    echo "ok    no function on the published path both converts a Double to 32 bits and can trap"
fi
absent "no wrapping 32-bit multiply on the published path" "$work/path.ll" ' = mul i32 ' '^$'
absent "no 64-bit value narrowed to 32 bits with a trap on the published path, except the date components of a day number" "$work/path.ll" 'icmp s(lt|gt) i64 [^,]+, (-2147483648|2147483647)$' '^CivilDay\.date\('
date_narrowings=$(grep -c -E '^CivilDay\.date\(.*icmp s(lt|gt) i64 [^,]+, (-2147483648|2147483647)$' "$work/path.ll")
if [ "$date_narrowings" -eq 6 ]; then
    echo "ok    the date components of a day number hold exactly three trap-checked narrowings"
else
    echo "FAIL  the date components of a day number hold $date_narrowings limit compares, not six"
    status=1
fi
present "the scope reaches the time reader nested inside the cell codec" '^readHhmm #[0-9]+ .* in (static )?DeltaCellsCodec\.decode' '.'
present "the even-odd edge products are 64-bit" '^LocalityIndex\.contains' 'smul\.with\.overflow\.i64|mul (nsw )?i64'
present "distances round to 64-bit millimetres" '^LocalityIndex\.(haversineMm|edgeDistanceMm)' 'fptosi double [^ ]+ to i64'
present "day numbers are 64-bit" '^CivilDay\.dayNumber' 'i64'
present "the scope reaches the hour setter" '^DateComponents\.settingHour\(' 'fptosi double [^ ]+ to i32'
present "the scope reaches the Hanafi shift" '^PrayerTimes\.hanafiShiftMinutes\(' 'fptosi double [^ ]+ to i32'
present "the scope reaches the solar day" '^SolarDay\.afternoonHours\(' '.'
present "the scope reaches the header parser" 'HeaderJSON\.parse\(' '.'

exit $status
