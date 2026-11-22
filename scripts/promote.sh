#!/usr/bin/env bash
# The new version looked good: make it the stable version.
#
#   scripts/promote.sh canary | ab-testing | shadow
#
# (Rolling update and blue-green promote themselves during deploy.sh.)
source "$(dirname "$0")/lib.sh"

[ $# -eq 1 ] || die "Usage: $0 canary|ab-testing|shadow"
STRATEGY=$1
NS=$(ns_for "$STRATEGY")

case "$STRATEGY" in
    canary) from=aceest-canary; to=aceest-stable ;;
    ab-testing) from=aceest-b; to=aceest-a ;;
    shadow) from=aceest-shadow; to=aceest-live ;;
    *) die "Nothing to promote for $STRATEGY" ;;
esac

new=$(current_image "$NS" "$from")
[ -n "$new" ] || die "$from not found"
log "Promoting $new: $to now runs it"
set_image "$NS" "$to" "$new"
wait_rollout "$NS" "$to"
check_version "$NS" "$to" "$new"

case "$STRATEGY" in
    canary) kubectl -n "$NS" scale deployment/aceest-canary --replicas=0 ;;
    shadow) kubectl -n "$NS" scale deployment/aceest-shadow --replicas=0 ;;
esac
log "Promotion of $STRATEGY done"
