#!/usr/bin/env bash
# Print the URL of every strategy and which version(s) answer there.
#
#   scripts/endpoints.sh          # 10 requests per strategy
#   scripts/endpoints.sh 20       # 20 requests per strategy
source "$(dirname "$0")/lib.sh"

N=${1:-10}
ask() { curl -fsS --max-time 3 "$@" 2>/dev/null \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])' || echo "no answer"; }

for s in $STRATEGIES; do
    url=$(url_for "$s")
    echo
    echo "== $s: $url"
    for _ in $(seq "$N"); do ask "$url/version"; done | sort | uniq -c \
        | awk '{print "   " $1 " x version " $2}'
done

echo
echo "== blue-green preview (idle colour): http://$(node_ip):30092"
echo "   version $(ask "http://$(node_ip):30092/version")"
echo
echo "== A/B forced variants:"
echo "   X-Variant: A -> version $(ask -H 'X-Variant: A' "$(url_for ab-testing)/version")"
echo "   X-Variant: B -> version $(ask -H 'X-Variant: B' "$(url_for ab-testing)/version")"
echo
echo "== shadow: last requests seen by the shadow pod (users never saw its answers):"
kubectl -n aceest-shadow logs deploy/aceest-shadow 2>/dev/null | grep -v 'GET /health' | tail -5 | sed 's/^/   /' || true
