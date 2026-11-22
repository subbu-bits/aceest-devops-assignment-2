#!/usr/bin/env bash
# Return a strategy to its last stable version.
#
#   scripts/rollback.sh STRATEGY
#
#   rolling     kubectl rollout undo (previous ReplicaSet)
#   blue-green  switch live traffic back to the other colour
#   canary      scale the canary to 0 (all traffic to stable)
#   ab-testing  put variant B back on variant A's image (everyone gets A)
#   shadow      scale the shadow to 0 (users were never affected)
source "$(dirname "$0")/lib.sh"

[ $# -eq 1 ] || die "Usage: $0 STRATEGY|all"
STRATEGY=$1
if [ "$STRATEGY" = all ]; then
    for s in $STRATEGIES; do bash "$0" "$s" || true; done
    exit 0
fi
NS=$(ns_for "$STRATEGY")

case "$STRATEGY" in
    rolling)
        if kubectl -n "$NS" rollout undo deployment/aceest; then
            wait_rollout "$NS" aceest
        else
            log "Nothing to undo (first deployment?)"
        fi
        ;;
    blue-green)
        live=$(kubectl -n "$NS" get svc aceest -o jsonpath='{.spec.selector.color}')
        if [ "$live" = blue ]; then other=green; else other=blue; fi
        exists "$NS" "aceest-$other" || die "aceest-$other does not exist - nothing to roll back to"
        wait_rollout "$NS" "aceest-$other" \
            || die "aceest-$other is not healthy - staying on $live"
        log "Switching live traffic back: $live -> $other"
        kubectl -n "$NS" patch svc aceest -p "{\"spec\":{\"selector\":{\"app\":\"aceest\",\"color\":\"$other\"}}}"
        kubectl -n "$NS" patch svc aceest-preview -p "{\"spec\":{\"selector\":{\"app\":\"aceest\",\"color\":\"$live\"}}}"
        ;;
    canary)
        kubectl -n "$NS" scale deployment/aceest-canary --replicas=0
        ;;
    ab-testing)
        stable=$(current_image "$NS" aceest-a)
        log "Variant B -> $stable (same as A)"
        set_image "$NS" aceest-b "$stable"
        wait_rollout "$NS" aceest-b
        ;;
    shadow)
        kubectl -n "$NS" scale deployment/aceest-shadow --replicas=0
        ;;
esac
log "Rollback of $STRATEGY done"
