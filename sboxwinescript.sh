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

wget -N https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x winetricks

export WINEPREFIX="$SCRIPTDIR/sbox/.wine"
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEARCH=win64
export WINEDEBUG=fixme-all
export DISPLAY=:$DPY_NUM
./winetricks -q vcrun2022 > winescript_log.txt 2>&1
./winetricks -q dotnet7 >> winescript_log.txt 2>&1
./winetricks -q win10 >> winescript_log.txt 2>&1
rm -rf ~/.cache/winetricks

exec 6>&-
kill $XVFB_PID

exit 0
