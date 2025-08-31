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

export WINEPREFIX="$SCRIPTDIR/arkse/.wine"
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEARCH=win64
export WINEDEBUG=fixme-all
export DISPLAY=:$DPY_NUM
export XDG_RUNTIME_DIR=/tmp

[[ -f winetricks ]] && rm -f winetricks
wget -q https://raw.githubusercontent.com/Winetricks/winetricks/refs/tags/20250102/src/winetricks
chmod +x winetricks

PACKAGES="vcrun2019 sound=disabled"
echo "" > winescript_log.txt 2>&1
for PACKAGE in $PACKAGES; do
  ./winetricks -q $PACKAGE >> winescript_log.txt 2>&1
done
rm -rf ~/.cache/winetricks

exec 6>&-
kill $XVFB_PID

exit 0
