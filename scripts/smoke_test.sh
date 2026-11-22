#!/usr/bin/env bash
# Check that a running deployment answers correctly.
#
#   scripts/smoke_test.sh URL [EXPECTED_VERSION]
#
# Passes when /health is healthy and (if given) /version matches.
set -euo pipefail

URL=${1:?Usage: $0 URL [EXPECTED_VERSION]}
EXPECTED=${2:-}

for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if body=$(curl -fsS --max-time 5 "$URL/health" 2>/dev/null) \
            && echo "$body" | grep -q healthy; then
        break
    fi
    echo "Waiting for $URL/health (attempt $attempt)..."
    sleep 3
    [ "$attempt" = 10 ] && { echo "FAIL: $URL/health not healthy"; exit 1; }
done
echo "OK: $URL/health is healthy"

curl -fsS --max-time 5 "$URL/programs" >/dev/null
echo "OK: $URL/programs answers"

if [ -n "$EXPECTED" ]; then
    got=$(curl -fsS --max-time 5 "$URL/version" \
        | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])')
    if [ "$got" != "$EXPECTED" ]; then
        echo "FAIL: $URL runs version $got, expected $EXPECTED"
        exit 1
    fi
    echo "OK: $URL runs version $got"
fi
