#!/usr/bin/env bash
# Deploy a new image with one of the five strategies.
#
#   scripts/deploy.sh STRATEGY NEW_IMAGE [STABLE_IMAGE]
#
#   STRATEGY      rolling | blue-green | canary | ab-testing | shadow | all
#   NEW_IMAGE     the version to roll out, e.g. user/aceest-fitness:3.2.4
#   STABLE_IMAGE  the current version. Only needed the first time a strategy
#                 is set up; later the image already running is used.
#
# If the new version fails (pods never become Ready, or report the wrong
# version) the script rolls back automatically and exits with an error.
source "$(dirname "$0")/lib.sh"

[ $# -ge 2 ] || die "Usage: $0 STRATEGY NEW_IMAGE [STABLE_IMAGE]"
STRATEGY=$1
NEW=$2
STABLE_ARG=${3:-}

# Pick the stable image: explicit argument > image already running > NEW.
stable_image() { # ns deployment
    if [ -n "$STABLE_ARG" ]; then echo "$STABLE_ARG"; return; fi
    local img
    img=$(current_image "$1" "$2")
    echo "${img:-$NEW}"
}

# Make sure the stable deployment exists and runs the stable image.
ensure_stable() { # ns deployment manifest
    local img
    img=$(stable_image "$1" "$2")
    if ! exists "$1" "$2" || [ -n "$STABLE_ARG" ]; then
        log "Stable $2 -> $img"
        apply_tpl "$3" IMAGE="$img"
    fi
    wait_rollout "$1" "$2"
}

deploy_rolling() {
    local ns=aceest-rolling
    kubectl apply -f "$K8S_DIR/rolling/service.yaml"
    if exists $ns aceest; then
        log "Rolling update: $(current_image $ns aceest) -> $NEW"
        set_image $ns aceest "$NEW"
    else
        log "First deployment of $NEW"
        apply_tpl "$K8S_DIR/rolling/deployment.yaml" IMAGE="$NEW"
        kubectl -n $ns annotate deployment/aceest \
            kubernetes.io/change-cause="image $NEW" --overwrite >/dev/null
    fi
    if wait_rollout $ns aceest && check_version $ns aceest "$NEW"; then
        log "Rolling update finished"
    else
        log "Rolling update FAILED - rolling back"
        bash "$(dirname "$0")/rollback.sh" rolling
        return 1
    fi
}

deploy_blue_green() {
    local ns=aceest-bluegreen live idle
    live=$(kubectl -n $ns get svc aceest -o jsonpath='{.spec.selector.color}' 2>/dev/null || true)
    if [ -z "$live" ]; then
        # First time: blue runs the stable version and gets the traffic.
        live=blue
        log "Setting up blue-green: blue (live) -> $(stable_image $ns aceest-blue)"
        apply_tpl "$K8S_DIR/blue-green/deployment.yaml" COLOR=blue \
            IMAGE="$(stable_image $ns aceest-blue)"
        apply_tpl "$K8S_DIR/blue-green/service.yaml" LIVE=blue IDLE=green
        wait_rollout $ns aceest-blue
    fi
    if [ "$live" = blue ]; then idle=green; else idle=blue; fi
    if [ "$(current_image $ns aceest-$live)" = "$NEW" ]; then
        log "$live is already live with $NEW - nothing to switch"
        return 0
    fi

    log "Deploying $NEW to idle colour: $idle"
    apply_tpl "$K8S_DIR/blue-green/deployment.yaml" COLOR=$idle IMAGE="$NEW"
    if ! { wait_rollout $ns aceest-$idle && check_version $ns aceest-$idle "$NEW"; }; then
        log "$idle FAILED its checks - users stay on $live, nothing switched"
        return 1
    fi
    log "Switching live traffic: $live -> $idle (preview now points at $live)"
    kubectl -n $ns patch svc aceest -p "{\"spec\":{\"selector\":{\"app\":\"aceest\",\"color\":\"$idle\"}}}"
    kubectl -n $ns patch svc aceest-preview -p "{\"spec\":{\"selector\":{\"app\":\"aceest\",\"color\":\"$live\"}}}"
    log "Blue-green switch done. Old version is still running on $live for instant rollback."
}

deploy_canary() {
    local ns=aceest-canary
    kubectl apply -f "$K8S_DIR/canary/service.yaml"
    ensure_stable $ns aceest-stable "$K8S_DIR/canary/deployment-stable.yaml"
    log "Canary: 1 pod of $NEW next to 3 stable pods (~25% of traffic)"
    apply_tpl "$K8S_DIR/canary/deployment-canary.yaml" IMAGE="$NEW"
    if wait_rollout $ns aceest-canary && check_version $ns aceest-canary "$NEW"; then
        log "Canary is live. Watch it, then run: scripts/promote.sh canary"
    else
        log "Canary FAILED - removing it"
        bash "$(dirname "$0")/rollback.sh" canary
        return 1
    fi
}

deploy_ab() {
    local ns=aceest-ab
    kubectl apply -f "$K8S_DIR/ab-testing/services.yaml"
    ensure_stable $ns aceest-a "$K8S_DIR/ab-testing/deployment-a.yaml"
    log "A/B: variant B -> $NEW"
    apply_tpl "$K8S_DIR/ab-testing/deployment-b.yaml" IMAGE="$NEW"
    kubectl apply -f "$K8S_DIR/ab-testing/router.yaml"
    if wait_rollout $ns aceest-b && check_version $ns aceest-b "$NEW" \
            && wait_rollout $ns router; then
        log "A/B test running. Users are split 50/50; header X-Variant: A|B forces a variant."
    else
        log "Variant B FAILED - sending everyone to A"
        bash "$(dirname "$0")/rollback.sh" ab-testing
        return 1
    fi
}

deploy_shadow() {
    local ns=aceest-shadow
    kubectl apply -f "$K8S_DIR/shadow/services.yaml"
    ensure_stable $ns aceest-live "$K8S_DIR/shadow/deployment-live.yaml"
    log "Shadow: $NEW receives a copy of all traffic"
    apply_tpl "$K8S_DIR/shadow/deployment-shadow.yaml" IMAGE="$NEW"
    kubectl apply -f "$K8S_DIR/shadow/router.yaml"
    if wait_rollout $ns aceest-shadow && check_version $ns aceest-shadow "$NEW" \
            && wait_rollout $ns router; then
        log "Shadow running. See mirrored requests: kubectl -n $ns logs deploy/aceest-shadow"
    else
        log "Shadow FAILED - stopping it (users were never affected)"
        bash "$(dirname "$0")/rollback.sh" shadow
        return 1
    fi
}

kubectl apply -f "$K8S_DIR/namespaces.yaml" >/dev/null

run() {
    case "$1" in
        rolling) deploy_rolling ;;
        blue-green) deploy_blue_green ;;
        canary) deploy_canary ;;
        ab-testing) deploy_ab ;;
        shadow) deploy_shadow ;;
        *) ns_for "$1" >/dev/null ;;
    esac
    log "$1 endpoint: $(url_for "$1")"
}

if [ "$STRATEGY" = all ]; then
    failed=0
    for s in $STRATEGIES; do
        log "########## $s ##########"
        run "$s" || failed=1
    done
    exit $failed
fi
run "$STRATEGY"
