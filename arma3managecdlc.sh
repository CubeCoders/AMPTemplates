#!/bin/bash
# Usage: arma3managecdlc.sh <depotid> <codename> <rootdir> <basedir>
# Downloads a single Arma 3 Creator DLC via its dedicated Steam depot (on the
# 'creatordlc' branch) instead of installing the full ~100GB creatordlc branch.
set -e

APPID=233780
BRANCH=creatordlc
DEPOTID="$1"
CODENAME="$2"
ROOTDIR="$3"
BASEDIR="$4"

STEAMCMD="${ROOTDIR}steamcmd.sh"
APPINFO="${ROOTDIR}appinfo_${APPID}.txt"
# On Linux, SteamCMD's actual binary runs from a linux32/ subfolder, and
# download_depot's default destination is relative to that working directory,
# not the top-level RootDir (unlike steamcmd.exe on Windows).
DOWNLOADDIR="${ROOTDIR}steamapps/content/app_${APPID}/depot_${DEPOTID}"
DOWNLOADDIR_LINUX32="${ROOTDIR}linux32/steamapps/content/app_${APPID}/depot_${DEPOTID}"

"$STEAMCMD" +login anonymous +app_info_print $APPID +quit > "$APPINFO" 2>&1

GID=$(awk -v depot="\"$DEPOTID\"" -v branch="\"$BRANCH\"" '
BEGIN { indepot=0; depth=0; inbranch=0 }
{
  if (indepot == 0 && $0 ~ ("^[[:space:]]*" depot "[[:space:]]*$")) {
    indepot=1; depth=0; next
  }
  if (indepot == 1) {
    if ($0 ~ /{/) depth++
    if ($0 ~ /}/) {
      depth--
      if (depth <= 0) { indepot=0; inbranch=0 }
    }
    if (inbranch == 0 && $0 ~ ("^[[:space:]]*" branch "[[:space:]]*$")) {
      inbranch=1; next
    }
    if (inbranch == 1 && $0 ~ /"gid"/) {
      line=$0
      gsub(/[^0-9]/, "", line)
      print line
      exit
    }
  }
}
' "$APPINFO")

if [ -z "$GID" ]; then
    echo "ERROR: Could not resolve manifest ID for depot $DEPOTID on branch $BRANCH"
    exit 1
fi

echo "Resolved depot $DEPOTID ($CODENAME) to manifest $GID on branch $BRANCH"

"$STEAMCMD" +login anonymous +download_depot $APPID $DEPOTID $GID +quit

if [ -d "$DOWNLOADDIR_LINUX32" ]; then
    DOWNLOADDIR="$DOWNLOADDIR_LINUX32"
elif [ ! -d "$DOWNLOADDIR" ]; then
    echo "ERROR: Depot download did not produce expected folder: $DOWNLOADDIR or $DOWNLOADDIR_LINUX32"
    exit 1
fi

cp -rf "$DOWNLOADDIR"/* "$BASEDIR"
rm -rf "$DOWNLOADDIR"
rm -f "$APPINFO"

echo "Installed Creator DLC '$CODENAME' (depot $DEPOTID) into $BASEDIR"
