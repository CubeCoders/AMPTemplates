#!/bin/bash
# Downloads the rAthena source from GitHub and builds it.
# Usage: rathenaupdate.sh <branch, tag or commit> <renewal|prerenewal> [packet version] [vip: true|false]

REF="${1:-master}"
FLAGS=""
[[ "$2" == "prerenewal" ]] && FLAGS="--enable-prere=yes"
if [[ -n "$3" ]]; then
  [[ "$3" =~ ^[0-9]{8}$ ]] || { echo "Packet version must be a date like 20211103"; exit 1; }
  FLAGS="$FLAGS --enable-packetver=$3"
fi
[[ "${4,,}" == "true" ]] && FLAGS="$FLAGS --enable-vip=yes"
FLAGS="${FLAGS# }"
BASEDIR=$(dirname "$(readlink -f "$0")")
SERVERDIR="$BASEDIR/server"
SOURCE_STAMP="$SERVERDIR/.amp-source"
BUILD_STAMP="$SERVERDIR/.amp-build"

for tool in gcc g++ make wget tar; do
  command -v "$tool" >/dev/null 2>&1 || { echo "'$tool' is not installed. This template needs to run in a container"; exit 1; }
done
[[ "$REF" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "Invalid rAthena version '$REF'"; exit 1; }

SHA=$(wget -qO- "https://api.github.com/repos/rathena/rathena/commits/$REF" | grep -o '"sha": *"[0-9a-f]\{40\}"' | head -n 1 | grep -o '[0-9a-f]\{40\}')
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "Could not find rAthena version '$REF' on GitHub"; exit 1; }
echo "rAthena '$REF' is at commit ${SHA:0:10}"

if [[ -x "$SERVERDIR/map-server" && -f "$BUILD_STAMP" && "$(cat "$BUILD_STAMP")" == "$SHA $FLAGS" ]]; then
  echo "rAthena is already up to date. Skipping build"
  exit 0
fi

mkdir -p "$SERVERDIR"
if [[ ! -f "$SOURCE_STAMP" || "$(cat "$SOURCE_STAMP")" != "$SHA" ]]; then
  echo "Downloading rAthena source..."
  TMP="$BASEDIR/rathena-src.tar.gz"
  rm -f "$TMP"
  wget -qO "$TMP" "https://github.com/rathena/rathena/archive/$SHA.tar.gz" || { echo "Download from GitHub failed"; rm -f "$TMP"; exit 1; }
  tar -xzf "$TMP" -C "$SERVERDIR" --strip-components=1 || { echo "Extracting the rAthena source failed"; rm -f "$TMP"; exit 1; }
  rm -f "$TMP"
  echo "$SHA" > "$SOURCE_STAMP"
fi

cd "$SERVERDIR" || exit 1
chmod +x configure athena-start function.sh 2>/dev/null
echo "Configuring rAthena${FLAGS:+ with: $FLAGS}"
# shellcheck disable=SC2086
./configure $FLAGS > "$BASEDIR/rathena-configure.log" 2>&1 || { tail -n 20 "$BASEDIR/rathena-configure.log"; echo "configure failed. See rathena-configure.log"; exit 1; }
echo "Building rAthena. This takes several minutes..."
make clean > /dev/null 2>&1
make server -j"$(nproc)" > "$BASEDIR/rathena-build.log" 2>&1 || { tail -n 30 "$BASEDIR/rathena-build.log"; echo "Build failed. See rathena-build.log"; exit 1; }
echo "$SHA $FLAGS" > "$BUILD_STAMP"
echo "rAthena built from commit ${SHA:0:10}"
