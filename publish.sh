#!/bin/bash
# Build and push w2vy/gammonbot to Docker Hub from THIS working tree.
# Pushes ONLY the tag you give. :latest moves only with --latest
# (Flux apps on :latest update themselves, so that is the deploy step).
# Usage: ./publish.sh <tag> [--latest]
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=w2vy/gammonbot
TAG=${1:?usage: ./publish.sh <tag> [--latest]}
LATEST=no
[[ ${2:-} == --latest ]] && LATEST=yes
[[ $TAG == latest ]] && { echo "Give a real tag; use --latest to move :latest."; exit 1; }
SHA=$(git rev-parse --short HEAD)
DIRTY=$(git status --porcelain -- gbot Dockerfile patch | wc -l)

echo "Building $IMAGE:$TAG from $(git branch --show-current)@$SHA ($DIRTY uncommitted files in gbot/Dockerfile/patch)"
docker build --platform=linux/amd64 \
    --label org.opencontainers.image.revision="$SHA" \
    --label gammonbot.uncommitted="$DIRTY" \
    -t "$IMAGE:$TAG" .

[[ $LATEST == yes ]] && targets="$IMAGE:$TAG AND $IMAGE:latest" || targets="$IMAGE:$TAG only (:latest unchanged)"
read -r -p "Push $targets to Docker Hub? [y/N] " ok
[[ $ok == [yY] ]] || { echo "Not pushed."; exit 0; }
docker push "$IMAGE:$TAG"
if [[ $LATEST == yes ]]; then
    docker tag "$IMAGE:$TAG" "$IMAGE:latest"
    docker push "$IMAGE:latest"
fi
