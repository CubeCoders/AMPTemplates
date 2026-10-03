#!/bin/bash
# Installs, updates and removes the Thunderstore mods listed in the "Thunderstore Mods" setting.
# Usage: ./managemods.sh <bepinex_install> <valheim_plus_install>
# Each list line is Namespace/Name, Namespace/Name-1.2.3, Namespace-Name-1.2.3 or a thunderstore.io package URL.
# A version in the line pins the mod to it, otherwise the latest version is installed.
set -euo pipefail

BEPINEX_ON="${1:-false}"
VPLUS_ON="${2:-false}"
LIST="./Valheim/thunderstore-mods.txt"
BEPINEX="./Valheim/896660/BepInEx"
PLUGINS="$BEPINEX/plugins"
STATE="$PLUGINS/.thunderstore-versions"
API="https://thunderstore.io/api/experimental/package"

# The template installs BepInEx itself
SKIP_RE='^denikson/BepInExPack_Valheim$'
# Configs shipped by ValheimPlus would bring back the legacy valheim_plus.cfg
NOCONFIG_RE='^Grantapher/ValheimPlus'
VPLUS_RE='^Grantapher/ValheimPlus'
VER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

WANT=()
declare -A PIN=()

parse_entry() {
  local line="$1" ns="" name="" ver=""
  if [[ "$line" =~ ^https?://([a-z0-9-]+\.)?thunderstore\.io/c/[^/]+/p/([^/?#]+)/([^/?#]+)(/v/([^/?#]+))? ]]; then
    ns="${BASH_REMATCH[2]}"; name="${BASH_REMATCH[3]}"; ver="${BASH_REMATCH[5]}"
  elif [[ "$line" =~ ^https?://([a-z0-9-]+\.)?thunderstore\.io/package/download/([^/?#]+)/([^/?#]+)/([^/?#]+) ]]; then
    ns="${BASH_REMATCH[2]}"; name="${BASH_REMATCH[3]}"; ver="${BASH_REMATCH[4]}"
  elif [[ "$line" =~ ^https?://([a-z0-9-]+\.)?thunderstore\.io/package/([^/?#]+)/([^/?#]+) ]]; then
    ns="${BASH_REMATCH[2]}"; name="${BASH_REMATCH[3]}"
  elif [[ "$line" =~ ^([A-Za-z0-9_]+)/([A-Za-z0-9_.-]+)$ ]]; then
    ns="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"
  elif [[ "$line" =~ ^([A-Za-z0-9_]+)/([A-Za-z0-9_.-]+)/([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    ns="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"; ver="${BASH_REMATCH[3]}"
  elif [[ "$line" =~ ^([A-Za-z0-9_]+)-(.+)-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    ns="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"; ver="${BASH_REMATCH[3]}"
  else
    echo "!! Unrecognised Thunderstore mod entry: $line" >&2; exit 1
  fi
  # A version can also be appended to the name, e.g. Namespace/Name-1.2.3
  if [[ -z "$ver" && "$name" =~ ^(.+)-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    name="${BASH_REMATCH[1]}"; ver="${BASH_REMATCH[2]}"
  fi
  if [[ -n "$ver" && ! "$ver" =~ $VER_RE ]]; then
    echo "!! Invalid version '$ver' in entry: $line" >&2; exit 1
  fi
  WANT+=("$ns/$name")
  [[ -n "$ver" ]] && PIN["$ns/$name"]="$ver"
  return 0
}

if [[ -f "$LIST" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" || "$line" == \#* ]] && continue
    parse_entry "$line"
  done < "$LIST"
fi

if [[ "$BEPINEX_ON" != "true" && "$VPLUS_ON" != "true" ]]; then
  if ((${#WANT[@]})); then
    echo "!! Thunderstore mods need Install BepInEx or Install Valheim Plus to be enabled" >&2; exit 1
  fi
  exit 0
fi
if ! ((${#WANT[@]})) && [[ ! -s "$STATE" ]]; then
  echo "No Thunderstore mods configured"; exit 0
fi
[[ -d "$BEPINEX/core" ]] || { echo "!! BepInEx not found at $BEPINEX" >&2; exit 1; }

OWNER="$(stat -c '%u:%g' "$BEPINEX")"   # captured before anything is copied in
mkdir -p "$PLUGINS" "$BEPINEX/config" "$BEPINEX/patchers"

declare -A HAVE=()
if [[ -f "$STATE" ]]; then
  while read -r k v; do [[ -n "$k" ]] && HAVE[$k]="$v"; done < "$STATE"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
declare -A SEEN=() KEEP=()
INSTALLED=(); UPDATED=(); REMOVED=()

install_pkg() {
  local id="$1"
  [[ -n "${SEEN[$id]:-}" ]] && return 0
  SEEN[$id]=1
  [[ "$id" =~ $SKIP_RE ]] && return 0
  if [[ "$VPLUS_ON" == "true" && "$id" =~ $VPLUS_RE ]]; then
    echo "Skipping $id, Install Valheim Plus is enabled"; return 0
  fi

  local pin="${PIN[$id]:-}" json
  json="$(wget -qO- "$API/$id/${pin:+$pin/}")" || { echo "!! Failed to query $id${pin:+ $pin} from Thunderstore" >&2; exit 1; }
  json="$(jq '.latest // .' <<<"$json")"
  local ver url
  ver="$(jq -r '.version_number' <<<"$json")"
  url="$(jq -r '.download_url' <<<"$json")"

  # Dependencies first. Strings look like Namespace-Name-1.2.3 and names can contain -
  local dep ns rest
  while read -r dep; do
    [[ -z "$dep" ]] && continue
    ns="${dep%%-*}"; rest="${dep#*-}"
    install_pkg "$ns/${rest%-*}"
  done < <(jq -r '.dependencies[]' <<<"$json")

  KEEP[$id]=1
  local old="${HAVE[$id]:-}"
  [[ "$old" == "$ver" ]] && return 0

  echo ">> $id ${old:+$old -> }$ver"
  local z="$TMP/${id//\//-}.zip" x="$TMP/${id//\//-}"
  wget -qO "$z" "$url" || { echo "!! Failed to download $id $ver" >&2; exit 1; }
  rm -rf "$x"; mkdir -p "$x"
  local rc=0; unzip -qo "$z" -d "$x" || rc=$?
  # 1 is a warning, e.g. zips made on Windows with backslash paths
  (( rc <= 1 )) || { echo "!! unzip failed ($rc) for $id" >&2; exit 1; }
  local f rel new
  find "$x" -depth -name '*\\*' | while read -r f; do
    rel="${f#"$x"/}"; new="$x/${rel//\\//}"; mkdir -p "$(dirname "$new")"; mv "$f" "$new"
  done
  rm -f "$x"/{manifest.json,icon.png,README.md,CHANGELOG.md}
  # Some zips ship world-writable modes
  chmod -R u+rwX,go+rX,go-w "$x"

  # A BepInEx/ tree is handled like the flat layout so the mod still gets its own folder
  if [[ -d "$x/BepInEx" ]]; then
    for f in plugins config patchers; do
      if [[ -d "$x/BepInEx/$f" ]]; then mkdir -p "$x/$f"; cp -R "$x/BepInEx/$f/." "$x/$f/"; fi
    done
    rm -rf "$x/BepInEx"
  fi

  local dest="$PLUGINS/${id//\//-}"
  rm -rf "$dest"

  [[ "$id" =~ $NOCONFIG_RE ]] && rm -rf "$x/config"
  if [[ -d "$x/config" ]]; then
    # Never overwrite existing configs
    (cd "$x/config" && find . -type f) | while read -r f; do
      [[ -e "$BEPINEX/config/$f" ]] || install -D -m 644 "$x/config/$f" "$BEPINEX/config/$f"
    done
    rm -rf "$x/config"
  fi
  if [[ -d "$x/patchers" ]]; then cp -R "$x/patchers/." "$BEPINEX/patchers/"; rm -rf "$x/patchers"; fi
  mkdir -p "$dest"
  if [[ -d "$x/plugins" ]]; then cp -R "$x/plugins/." "$dest/"; rm -rf "$x/plugins"; fi
  cp -R "$x/." "$dest/"
  rmdir "$dest" 2>/dev/null || true
  # Loose copies of the same DLLs directly in plugins/ would load twice
  if [[ -d "$dest" ]]; then
    while read -r f; do
      [[ -f "$PLUGINS/$f" ]] && { echo "   Removing loose plugins/$f"; rm -f "$PLUGINS/$f"; }
    done < <(find "$dest" -name '*.dll' -printf '%f\n')
  fi

  HAVE[$id]="$ver"
  if [[ -n "$old" ]]; then UPDATED+=("$id $old -> $ver"); else INSTALLED+=("$id $ver"); fi
  return 0
}

for m in "${WANT[@]}"; do install_pkg "$m"; done

# Remove mods this script installed that are no longer listed or needed as a dependency
for k in "${!HAVE[@]}"; do
  [[ -n "${KEEP[$k]:-}" ]] && continue
  rm -rf "${PLUGINS:?}/${k//\//-}"
  REMOVED+=("$k ${HAVE[$k]}")
  unset "HAVE[$k]"
done

for k in "${!HAVE[@]}"; do echo "$k ${HAVE[$k]}"; done | sort > "$STATE"

if [[ "$(id -u)" -eq 0 ]]; then chown -R "$OWNER" "$BEPINEX"; fi
chmod -R u+rwX,g+rX "$BEPINEX" 2>/dev/null || true

((${#UPDATED[@]}))   && { echo "Updated:";   printf '  %s\n' "${UPDATED[@]}"; }
((${#INSTALLED[@]})) && { echo "Installed:"; printf '  %s\n' "${INSTALLED[@]}"; }
((${#REMOVED[@]}))   && { echo "Removed:";   printf '  %s\n' "${REMOVED[@]}"; }
((${#UPDATED[@]} + ${#INSTALLED[@]} + ${#REMOVED[@]})) || echo "All Thunderstore mods are up to date"
exit 0
