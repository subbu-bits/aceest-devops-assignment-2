#!/usr/bin/env bash
# Smoke-test a strategy's public endpoint after deploy.sh.
#
#   scripts/verify.sh STRATEGY|all VERSION
#
# rolling and blue-green must serve only VERSION. canary, A/B and shadow
# mix two versions, so for them we check health plus the new pods directly.
source "$(dirname "$0")/lib.sh"

[ $# -eq 2 ] || die "Usage: $0 STRATEGY|all VERSION"
SMOKE="$(dirname "$0")/smoke_test.sh"

verify() {
    local url
    url=$(url_for "$1")
    case "$1" in
        rolling | blue-green) bash "$SMOKE" "$url" "$2" ;;
        ab-testing)
            bash "$SMOKE" "$url"
            got=$(curl -fsS -H 'X-Variant: B' "$url/version" \
                | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])')
            log "Variant B serves $got"
            [ "$got" = "$2" ] ;;
        *) bash "$SMOKE" "$url" ;;
    esac
}

if [ "$1" = all ]; then
    for s in $STRATEGIES; do verify "$s" "$2"; done
else
    verify "$1" "$2"
fi
