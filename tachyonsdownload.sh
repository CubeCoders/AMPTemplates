#!/bin/bash
# Downloads the Tachyons dedicated server from the developer's itch.io page
# (https://spektor.itch.io/tachyon) and installs the server folder into the
# instance. Server config files that already exist are kept.
target="${1:-tachyons}"
page="https://spektor.itch.io/tachyon"
keep="config.cfg hazards.cfg npc_races.cfg player_races.cfg"

fail() { echo "Tachyons server download failed: $1"; exit 1; }

mkdir -p "$target" && cd "$target" || fail "cannot open $target"
work="$PWD/.tachyons-download"
rm -rf "$work" && mkdir -p "$work" || fail "cannot create $work"
trap 'rm -rf "$work"' EXIT
cookies="$work/cookies.txt"

wget -q --keep-session-cookies --save-cookies "$cookies" -O "$work/page.html" "$page" || fail "could not reach $page"
token=$(grep -o 'name="csrf_token" value="[^"]*"' "$work/page.html" | head -n1 | sed 's/.*value="//; s/"$//')
[[ -n "$token" ]] || fail "could not read the download token from $page"
post="csrf_token=$(jq -rn --arg t "$token" '$t|@uri')"

dlpage=$(wget -q --keep-session-cookies --load-cookies "$cookies" --save-cookies "$cookies" --post-data "$post" -O - "$page/download_url" | jq -r '.url // empty')
[[ -n "$dlpage" ]] || fail "itch.io did not return a download page"
wget -q --keep-session-cookies --load-cookies "$cookies" --save-cookies "$cookies" -O "$work/downloads.html" "$dlpage" || fail "could not open the download page"

upload=$(grep -o 'data-upload_id="[0-9]*"[^<]*</a><div class="info_column"><div class="upload_name"><strong title="Tachyons [^"]*\.zip"' "$work/downloads.html" | head -n1)
uploadid=$(sed -n 's/^data-upload_id="\([0-9]*\)".*/\1/p' <<< "$upload")
version=$(sed -n 's/.*<strong title="\([^"]*\)"$/\1/p' <<< "$upload")
[[ -n "$uploadid" && -n "$version" ]] || fail "could not find the Tachyons zip on the itch.io download page"

if [[ -f TachyonsServer.jar && -f tachyons_version.txt && "$(tr -d '\r\n' < tachyons_version.txt)" == "$version" ]]; then
  echo "$version is already installed. Skipping"
  exit 0
fi

url=$(wget -q --keep-session-cookies --load-cookies "$cookies" --post-data "$post" -O - "$page/file/$uploadid?source=view_game&as_props=1" | jq -r '.url // empty')
[[ -n "$url" ]] || fail "itch.io did not return a download link"

echo "Downloading $version"
wget -q -O "$work/tachyons.zip" "$url" || fail "download from itch.io failed"
unzip -q "$work/tachyons.zip" '*/server/*' -d "$work/x" || fail "could not extract the server folder"
src=$(find "$work/x" -mindepth 2 -maxdepth 2 -type d -name server | head -n1)
[[ -n "$src" && -f "$src/TachyonsServer.jar" ]] || fail "the downloaded zip has no server folder"

for f in $keep; do
  [[ -f "$f" ]] && rm -f "$src/$f"
done
cp -rf "$src/." . || fail "could not copy the server files"

echo "$version" > tachyons_version.txt
echo "$version installed"
