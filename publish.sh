#!/bin/bash
# Build and push w2vy/gammonbot to Docker Hub from THIS working tree.
# Tags :latest plus a date tag (:YYYYMMDD) so a bad push can be rolled back.
# Usage: ./publish.sh [date-tag]     (default: today)
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=w2vy/gammonbot
TAG=${1:-$(date +%Y%m%d)}
SHA=$(git rev-parse --short HEAD)
DIRTY=$(git status --porcelain -- gbot Dockerfile patch | wc -l)

echo "Building $IMAGE:$TAG from $(git branch --show-current)@$SHA ($DIRTY uncommitted files in gbot/Dockerfile/patch)"
docker build --platform=linux/amd64 \
    --label org.opencontainers.image.revision="$SHA" \
    --label gammonbot.uncommitted="$DIRTY" \
    -t "$IMAGE:$TAG" -t "$IMAGE:latest" .

read -r -p "Push $IMAGE:$TAG and :latest to Docker Hub? [y/N] " ok
[[ $ok == [yY] ]] || { echo "Not pushed."; exit 0; }
docker push "$IMAGE:$TAG"
docker push "$IMAGE:latest"
