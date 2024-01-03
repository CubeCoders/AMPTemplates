#!/bin/bash

SCRIPT_NAME=$(echo \"$0\" | xargs readlink -f)
SCRIPTDIR=$(dirname "$SCRIPT_NAME")

exec 6>display.log
/usr/bin/Xvfb -displayfd 6 &
XVFB_PID=$!
while [[ ! -s display.log ]]; do
  sleep 1
done
read -r DPY_NUM < display.log
rm display.log

export WINEPREFIX="$SCRIPTDIR/subsistence/.wine"
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEARCH=win64
export WINEDEBUG=fixme-all
export DISPLAY=:$DPY_NUM

wget -N https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x winetricks

./winetricks -q win7 > winescript_log.txt 2>&1
./winetricks -q vcrun6 >> winescript_log.txt 2>&1
./winetricks -q vcrun2019 >> winescript_log.txt 2>&1
./winetricks -q corefonts >> winescript_log.txt 2>&1
./winetricks -q d3dcompiler_43 >> winescript_log.txt 2>&1
./winetricks -q d3dx9 >> winescript_log.txt 2>&1
./winetricks -q dotnet40 >> winescript_log.txt 2>&1

rm -rf ~/.cache/winetricks ~/.cache/fontconfig

exec 6>&-
kill $XVFB_PID

exit 0
