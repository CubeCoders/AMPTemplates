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

export WINEPREFIX="$SCRIPTDIR/space-engineers/.wine"
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEARCH=win64
export WINEDEBUG=fixme-all
export DISPLAY=:$DPY_NUM

[[ -f winetricks ]] && rm -f winetricks
wget -q https://raw.githubusercontent.com/Winetricks/winetricks/refs/tags/20260125/src/winetricks
chmod +x winetricks

PACKAGES="corefonts vcrun2022 dotnet48"
echo "" > winescript_log.txt 2>&1
for PACKAGE in $PACKAGES; do
  ./winetricks -q $PACKAGE >> winescript_log.txt 2>&1
done
rm -rf ~/.cache/winetricks ~/.cache/fontconfig

# Set Wine prefix to Windows 10 and use GDI renderer for Direct3D: see https://github.com/OwendB1/Linux-SE-Tools/blob/production/torch-wrapper
/usr/bin/wine reg add "HKCU\\Software\\Wine\\Version" /v Version /t REG_SZ /d win10 /f >/dev/null
/usr/bin/wine reg add "HKCU\\Software\\Wine\\AppDefaults\\steamcmd.exe" /v Version /t REG_SZ /d win10 /f >/dev/null
/usr/bin/wine reg add "HKCU\\Software\\Wine\\Direct3D" /v renderer /t REG_SZ /d gdi /f >/dev/null

exec 6>&-
kill $XVFB_PID

exit 0
