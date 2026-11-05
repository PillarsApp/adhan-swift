#!/bin/sh
set -u

if [ $# -ne 1 ]; then
    echo "usage: $0 <path to the Dart data release's MANIFEST>" >&2
    exit 2
fi

manifest=$1
root=$(cd "$(dirname "$0")/.." && pwd)
resources="$root/Sources/Resources"
status=0

if command -v shasum >/dev/null 2>&1; then
    hash_file() { shasum -a 256 "$1" | cut -d' ' -f1; }
elif command -v sha256sum >/dev/null 2>&1; then
    hash_file() { sha256sum "$1" | cut -d' ' -f1; }
else
    echo "neither shasum nor sha256sum is available" >&2
    exit 2
fi

manifest_hash() {
    awk -F'\t' -v name="$1" '$1 == "output" && $2 == name { print $NF }' "$manifest"
}

check() {
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: $2 != $3"
        status=1
    fi
}

times=$(hash_file "$resources/malaysia_times.txt")
zones=$(hash_file "$resources/malaysia_zones.txt")
check "malaysia_times.txt matches the manifest" "$times" "$(manifest_hash malaysia_times.txt)"
check "malaysia_zones.txt matches the manifest" "$zones" "$(manifest_hash malaysia_zones.txt)"

if cmp -s "$manifest" "$resources/MALAYSIA_MANIFEST"; then
    echo "ok    MALAYSIA_MANIFEST is byte-identical to the given manifest"
else
    echo "FAIL  MALAYSIA_MANIFEST differs from the given manifest"
    status=1
fi

revision=$(sed -n 's/.*revision = "\([^"]*\)".*/\1/p' "$root/Sources/Malaysia/MalaysiaTimetable.swift")
check "MalaysiaTimetable.revision" "$revision" "$(printf '%.8s-%.8s' "$times" "$zones")"

exit $status
