#!/bin/bash
# Sets up the Wine prefix and the save folder link. Safe to run repeatedly:
# the prefix is only built when it doesn't exist yet.

SCRIPTDIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPTDIR" || exit 1

ROOTDIR="$SCRIPTDIR/aloft"
GAMEDIR="$ROOTDIR/1660080"
export WINEPREFIX="$ROOTDIR/.wine"
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEARCH=win64
export WINEDEBUG=-all

mkdir -p "$GAMEDIR"

# In a container on a Windows host, the instance folder is a Windows folder shared
# into the container. A Wine prefix there is too slow (winetricks hangs and the game
# fails to start), so the prefix lives on container storage instead and the saves
# stay in the instance folder. The prefix is rebuilt when the container is recreated.
# Detected by the filesystem type of the shared folder.
LOCAL_PREFIX=0
FSTYPE=$(findmnt -no FSTYPE -T "$SCRIPTDIR" 2>/dev/null | head -1)
[[ -z "$FSTYPE" ]] && FSTYPE=$(stat -f -c %T "$SCRIPTDIR" 2>/dev/null)
IN_CONTAINER=0
[[ -f /.dockerenv || -f /run/.containerenv ]] && IN_CONTAINER=1
echo "Instance folder filesystem: ${FSTYPE:-unknown} (container: $IN_CONTAINER)"
if [[ $IN_CONTAINER == 1 && "$FSTYPE" =~ ^(9p|v9fs|drvfs|fakeowner|cifs|smb.*|fuse.*|grpcfuse)$ ]]; then
  LOCAL_PREFIX=1
  CONTAINER_PREFIX="/tmp/aloft-wine"
  mkdir -p "$CONTAINER_PREFIX"
  if [[ ! -L "$WINEPREFIX" ]]; then
    rm -rf "$WINEPREFIX"
    ln -s "$CONTAINER_PREFIX" "$WINEPREFIX"
  fi
  export XDG_CACHE_HOME="/tmp/aloft-cache"
  echo "Instance folder is shared from the host: using container storage for the Wine prefix"
fi

if [[ ! -f "$WINEPREFIX/.aloft-ready" ]]; then
  echo "Creating Wine prefix"
  /usr/bin/wineboot --init --update
  /usr/bin/wineserver -w

  exec 6>display.log
  /usr/bin/Xvfb -displayfd 6 -nolisten tcp -nolisten unix &
  XVFB_PID=$!
  while [[ ! -s display.log ]]; do
    sleep 1
  done
  read -r DPY_NUM < display.log
  rm display.log
  export DISPLAY=:$DPY_NUM

  # Get Wine major version and the matching Wine Mono version
  WINE_VERSION=$(/usr/bin/wine --version | grep -oP '\d+' | head -1)
  case "$WINE_VERSION" in
    8) MONO_VERSION="8.1.0" ;;
    9) MONO_VERSION="9.4.0" ;;
    10|11) MONO_VERSION="10.4.1" ;;
    *)
      echo "Unsupported Wine version: $WINE_VERSION"
      exec 6>&-
      kill $XVFB_PID
      exit 1
      ;;
  esac

  [[ -f winetricks ]] && rm -f winetricks
  wget -q https://raw.githubusercontent.com/Winetricks/winetricks/refs/tags/20260125/src/winetricks
  chmod +x winetricks

  echo "Installing Wine Mono $MONO_VERSION"
  MONO_URL="https://dl.winehq.org/wine/wine-mono/${MONO_VERSION}/wine-mono-${MONO_VERSION}-x86.msi"
  wget -q -O "$WINEPREFIX/mono.msi" "$MONO_URL"
  /usr/bin/wine msiexec /i "$WINEPREFIX/mono.msi" /qn /quiet /norestart /log "$WINEPREFIX/mono_install.log"
  rm -f "$WINEPREFIX/mono.msi"

  PACKAGES="vcrun2022 sound=disabled"
  echo "" > winescript_log.txt 2>&1
  for PACKAGE in $PACKAGES; do
    echo "Installing $PACKAGE"
    ./winetricks -q $PACKAGE >> winescript_log.txt 2>&1
  done
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/winetricks"
  /usr/bin/wineserver -w

  exec 6>&-
  kill $XVFB_PID

  touch "$WINEPREFIX/.aloft-ready"
fi

# Save folder: Aloft writes to LocalLow in the Wine prefix; GAMEDIR/Aloft points at it.
LOCALLOW="$WINEPREFIX/drive_c/users/$(id -un)/AppData/LocalLow/Astrolabe Interactive"
mkdir -p "$LOCALLOW"
if [[ $LOCAL_PREFIX == 1 ]]; then
  # Saves live in the instance folder; the prefix links to them.
  [[ -L "$GAMEDIR/Aloft" ]] && rm -f "$GAMEDIR/Aloft"
  mkdir -p "$GAMEDIR/Aloft"
  if [[ ! -L "$LOCALLOW/Aloft" ]]; then
    rm -rf "$LOCALLOW/Aloft"
    ln -s "$GAMEDIR/Aloft" "$LOCALLOW/Aloft"
  fi

  # The game's DLLs crash while loading from the shared folder, so its .exe and .dll
  # files run from container storage. The originals are kept in the instance
  # (aloft/.binaries) so the copies can be rebuilt; SteamCMD replaces the links with
  # real files when it updates them, and they are moved across again here.
  ORIGDIR="$ROOTDIR/.binaries"
  BINDIR="/tmp/aloft-bin"
  if [[ -f "$GAMEDIR/Aloft.exe" || -L "$GAMEDIR/Aloft.exe" ]]; then
    echo "Linking the game binaries to container storage"
    cd "$GAMEDIR" || exit 1
    while IFS= read -r -d '' FILE; do
      FILE="${FILE#./}"
      if [[ -f "$FILE" && ! -L "$FILE" ]]; then
        mkdir -p "$ORIGDIR/$(dirname "$FILE")"
        mv -f "$FILE" "$ORIGDIR/$FILE"
      fi
    done < <(find . -path ./Aloft -prune -o -type f \( -iname '*.dll' -o -iname '*.exe' \) -print0)
    cd "$ORIGDIR" || exit 1
    while IFS= read -r -d '' FILE; do
      FILE="${FILE#./}"
      mkdir -p "$BINDIR/$(dirname "$FILE")"
      if ! cmp -s "$FILE" "$BINDIR/$FILE"; then
        cp -f "$FILE" "$BINDIR/$FILE" || exit 1
      fi
      ln -sfn "$BINDIR/$FILE" "$GAMEDIR/$FILE"
    done < <(find . -type f -print0)
    cd "$SCRIPTDIR" || exit 1
  fi
else
  # Saves live in the prefix (inside the instance); the game folder links to them.
  [[ -L "$LOCALLOW/Aloft" ]] && rm -f "$LOCALLOW/Aloft"
  mkdir -p "$LOCALLOW/Aloft"
  ln -sfn "../.wine/drive_c/users/$(id -un)/AppData/LocalLow/Astrolabe Interactive/Aloft" "$GAMEDIR/Aloft"
fi

exit 0
