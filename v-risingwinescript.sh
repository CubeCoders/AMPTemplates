#!/bin/bash

SCRIPT_NAME=$(echo \"$0\" | xargs readlink -f)
SCRIPTDIR=$(dirname "$SCRIPT_NAME")

exec 6>display.log
/usr/bin/Xvfb -displayfd 6 -nolisten tcp -nolisten unix &
XVFB_PID=$!
while [[ ! -s display.log ]]; do
  sleep 1
done
read -r DPY_NUM < display.log
rm display.log

export WINEPREFIX="$SCRIPTDIR/v-rising/.wine"
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEARCH=win64
export WINEDEBUG=fixme-all
export DISPLAY=:$DPY_NUM
export XDG_RUNTIME_DIR=/tmp

# Get Wine major version
WINE_VERSION=$(/usr/bin/wine --version | grep -oP '\d+' | head -1)

# Determine correct Wine Mono version
case "$WINE_VERSION" in
  8) MONO_VERSION="8.1.0" ;;
  9) MONO_VERSION="9.4.0" ;;
  10) MONO_VERSION="10.2.0" ;;
  *)
    echo "Unsupported Wine version: $WINE_VERSION"
    kill $XVFB_PID
    exit 1
    ;;
esac

# Setup winetricks and install Mono
[[ -f winetricks ]] && rm -f winetricks
wget -q https://raw.githubusercontent.com/Winetricks/winetricks/refs/tags/20250102/src/winetricks
chmod +x winetricks

MONO_URL="https://dl.winehq.org/wine/wine-mono/${MONO_VERSION}/wine-mono-${MONO_VERSION}-x86.msi"
wget -q -O "$WINEPREFIX/mono.msi" "$MONO_URL"
/usr/bin/wine msiexec /i "$WINEPREFIX/mono.msi" /qn /quiet /norestart /log "$WINEPREFIX/mono_install.log"

# Install vcrun2022 only if Wine version is not 10
if [[ "$WINE_VERSION" != "10" ]]; then
  ./winetricks -q vcrun2022 > winescript_log.txt 2>&1
fi

rm -rf ~/.cache/winetricks

exec 6>&-
kill $XVFB_PID
exit 0
