#!/usr/bin/env bash
# Shared helpers for deploy.sh, promote.sh, rollback.sh and endpoints.sh.
set -euo pipefail

K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../k8s" && pwd)"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-120s}"
STRATEGIES="rolling blue-green canary ab-testing shadow"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Namespace and public NodePort of each strategy.
ns_for() {
    case "$1" in
        rolling) echo aceest-rolling ;;
        blue-green) echo aceest-bluegreen ;;
        canary) echo aceest-canary ;;
        ab-testing) echo aceest-ab ;;
        shadow) echo aceest-shadow ;;
        *) die "Unknown strategy '$1'. Use one of: $STRATEGIES" ;;
    esac
}
port_for() {
    case "$1" in
        rolling) echo 30081 ;;
        blue-green) echo 30082 ;;
        canary) echo 30083 ;;
        ab-testing) echo 30084 ;;
        shadow) echo 30085 ;;
    esac
}

# Apply a manifest after replacing placeholders, e.g.
#   apply_tpl k8s/rolling/deployment.yaml IMAGE=user/aceest-fitness:3.2.4
apply_tpl() {
    local file=$1
    shift
    local args=()
    for kv in "$@"; do
        args+=(-e "s|__${kv%%=*}__|${kv#*=}|g")
    done
    sed "${args[@]}" "$file" | kubectl apply -f -
}

exists() { kubectl -n "$1" get deployment "$2" >/dev/null 2>&1; }

current_image() {
    kubectl -n "$1" get deployment "$2" \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true
}

set_image() { # ns deployment image
    kubectl -n "$1" set image "deployment/$2" "aceest=$3"
    kubectl -n "$1" annotate "deployment/$2" \
        kubernetes.io/change-cause="image $3" --overwrite >/dev/null
}

wait_rollout() {
    kubectl -n "$1" rollout status "deployment/$2" --timeout="$ROLLOUT_TIMEOUT"
}

# Version number from an image tag: user/aceest-fitness:3.2.4-b12 -> 3.2.4
version_of() {
    local tag=${1##*:}
    tag=${tag%%-*}
    if [[ $tag =~ ^[0-9]+(\.[0-9]+)*$ ]]; then echo "$tag"; fi
}

# Ask a pod of the deployment which version it is running.
pod_version() {
    kubectl -n "$1" exec "deploy/$2" -c aceest -- python -c \
        "import json,urllib.request;print(json.load(urllib.request.urlopen('http://localhost:5000/version'))['version'])"
}

# Check that the new pods really run the expected version.
check_version() { # ns deployment image
    local expected got
    expected=$(version_of "$3")
    [ -z "$expected" ] && { log "No version in tag $3, skipping version check"; return 0; }
    got=$(pod_version "$1" "$2") || return 1
    log "$1/$2 reports version $got (expected $expected)"
    [ "$got" = "$expected" ]
}

node_ip() {
    kubectl get nodes \
        -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
}

url_for() { echo "http://$(node_ip):$(port_for "$1")"; }
