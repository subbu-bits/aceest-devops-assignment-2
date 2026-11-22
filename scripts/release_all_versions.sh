#!/usr/bin/env bash
# Build, test and push an image for EVERY application version to Docker Hub.
# (Jenkins does this one version at a time when VERSION changes; this script
#  is a quick way to fill Docker Hub with all of them at once.)
#
#   scripts/release_all_versions.sh DOCKERHUB_USER
#
# Run `docker login` first.
set -euo pipefail

USER_NAME=${1:?Usage: $0 DOCKERHUB_USER}
IMAGE="$USER_NAME/aceest-fitness"
cd "$(dirname "$0")/.."
# Same list as SUPPORTED_VERSIONS in app.py
VERSIONS="1.0 1.1 2.0.1 2.2.4 3.2.4"
for v in $VERSIONS; do
    echo "==> Building $IMAGE:$v"
    docker build --build-arg APP_VERSION="$v" -t "$IMAGE:$v" .
    docker run --rm "$IMAGE:$v" pytest -q
    got=$(docker run --rm "$IMAGE:$v" python -c \
        "import app; print(app.app.config['APP_VERSION'])")
    [ "$got" = "$v" ] || { echo "Image reports $got, expected $v"; exit 1; }
    docker push "$IMAGE:$v"
done
docker tag "$IMAGE:${v}" "$IMAGE:latest"
docker push "$IMAGE:latest"
echo "==> Pushed: $VERSIONS (+ latest)"
