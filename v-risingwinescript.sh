#!/bin/bash

SCRIPT_NAME=$(echo \"$0\" | xargs readlink -f)
SCRIPTDIR=$(dirname "$SCRIPT_NAME")
/usr/bin/Xvfb :5 -screen 0 1024x768x16 -ac -nolisten tcp -nolisten unix &
xvfb_pid=$!
wget -N https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x winetricks
export WINEPREFIX=$SCRIPTDIR/v-rising/.wine
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEARCH=win64
export DISPLAY=:5
./winetricks -q vcrun2019 > winescript_log.txt 2>&1
./winetricks -q dotnet48 >> winescript_log.txt 2>&1
./winetricks -q dotnet6 >> winescript_log.txt 2>&1
rm -rf ~/.cache/winetricks
kill $xvfb_pid

exit 0
