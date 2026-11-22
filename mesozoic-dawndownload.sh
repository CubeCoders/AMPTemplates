#!/bin/bash
# Mesozoic Dawn server download for AMP.
# The developer only distributes the dedicated server as a container image
# (see https://mesozoicdawn.com/en/guides/server_setup). This script pulls that
# image straight from the developer's registry and unpacks the /app folder
# (the game server files) into the target directory. Docker is not needed.
#
# Usage: mesozoic-dawndownload.sh <target directory> [tag]

set -euo pipefail

DEST="${1:?target directory required}"
TAG="${2:-latest}"
REGISTRY="https://hkccr.ccs.tencentyun.com"
IMAGE="mesozoicdawn/gameserver"
ACCEPT="application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json"

for tool in curl tar gzip grep sed; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Missing required tool: $tool"; exit 1; }
done

mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
STAMP="$DEST/.image-digest"

echo "Requesting registry access token"
TOKEN="$(curl -fsSL "$REGISTRY/service/token?service=token-service&scope=repository:$IMAGE:pull" \
    | tr -d '\n\r ' | grep -o '"token":"[^"]*"' | sed 's/^"token":"//; s/"$//')"
[ -n "$TOKEN" ] || { echo "Could not get a registry token"; exit 1; }

fetch_manifest() {
    curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Accept: $ACCEPT" "$REGISTRY/v2/$IMAGE/manifests/$1" | tr -d '\n\r\t '
}

echo "Reading image manifest for tag $TAG"
MANIFEST="$(fetch_manifest "$TAG")"

# A multi-platform index points at one manifest per platform: pick linux/amd64.
if echo "$MANIFEST" | grep -q '"manifests":\['; then
    DIGEST="$(echo "$MANIFEST" | grep -o '"digest":"sha256:[0-9a-f]*","size":[0-9]*,"platform":{"architecture":"amd64","os":"linux"' \
        | head -n1 | grep -o 'sha256:[0-9a-f]*')"
    [ -n "$DIGEST" ] || { echo "No linux/amd64 image found"; exit 1; }
    MANIFEST="$(fetch_manifest "$DIGEST")"
else
    DIGEST="$TAG"
fi

LAYERS="$(echo "$MANIFEST" | sed 's/.*"layers":\[//' | grep -o '"digest":"sha256:[0-9a-f]*"' | grep -o 'sha256:[0-9a-f]*')"
[ -n "$LAYERS" ] || { echo "Image manifest lists no layers"; exit 1; }
LAYERSUM="$(echo "$LAYERS" | sha256sum | cut -d' ' -f1)"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$LAYERSUM" ] && [ -x "$DEST/GameServ.x86_64" ]; then
    echo "Server files are already up to date"
    exit 0
fi

WORK="$(mktemp -d "$DEST/.download.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root"

COUNT="$(echo "$LAYERS" | wc -l)"
N=0
for LAYER in $LAYERS; do
    N=$((N + 1))
    echo "Downloading layer $N of $COUNT"
    curl -fsSL --retry 3 -H "Authorization: Bearer $TOKEN" -o "$WORK/layer.tgz" "$REGISTRY/v2/$IMAGE/blobs/$LAYER"
    # Only the game folder (/app) is needed; layers without it are skipped.
    if tar -tzf "$WORK/layer.tgz" 2>/dev/null | grep '^app/' >/dev/null; then
        tar -xzf "$WORK/layer.tgz" -C "$WORK/root" --no-same-owner app
    fi
    rm -f "$WORK/layer.tgz"
done

[ -x "$WORK/root/app/GameServ.x86_64" ] || { echo "Server executable not found in image"; exit 1; }

# Replace the game code and bundled assets. Everything else in GameServ_Data
# (Database, Logs and any mods) is kept.
rm -rf "$DEST/GameServ_Data/il2cpp_data" "$DEST/GameServ_Data/Plugins" "$DEST/GameServ_Data/StreamingAssets/aa"
cp -a "$WORK/root/app/." "$DEST/"
chmod +x "$DEST/GameServ.x86_64"
echo "$LAYERSUM" > "$STAMP"
echo "Mesozoic Dawn server files updated"
