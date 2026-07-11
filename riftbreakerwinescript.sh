#!/bin/bash

# Installs the Windows runtime components required by The Riftbreaker dedicated
# server (a Windows-only application) into the Wine prefix so it can run on Linux.
# The Wine prefix itself is created/updated by the separate "Initialise Wine" update
# stage (wineboot --init --update), which never resets the prefix so saves survive.
# A marker file makes this script idempotent - the (slow) winetricks install runs
# only once per prefix and is skipped on subsequent updates.

SCRIPT_NAME=$(echo \"$0\" | xargs readlink -f)
SCRIPTDIR=$(dirname "$SCRIPT_NAME")

export WINEPREFIX="$SCRIPTDIR/riftbreaker/.wine"
export WINEARCH=win64
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEDEBUG=-all

MARKER="$WINEPREFIX/.rb-runtime-done"
[[ -f "$MARKER" ]] && exit 0

# winetricks needs a display, so spin up a temporary virtual framebuffer.
exec 6>display.log
/usr/bin/Xvfb -displayfd 6 -nolisten tcp -nolisten unix &
XVFB_PID=$!
while [[ ! -s display.log ]]; do
  sleep 1
done
read -r DPY_NUM < display.log
rm display.log
export DISPLAY=:$DPY_NUM

[[ -f winetricks ]] && rm -f winetricks
wget -q https://raw.githubusercontent.com/Winetricks/winetricks/refs/tags/20260125/src/winetricks
chmod +x winetricks

echo "" > winescript_log.txt 2>&1
for PACKAGE in vcrun2022 d3dcompiler_47; do
  ./winetricks -q $PACKAGE >> winescript_log.txt 2>&1
done
rm -rf ~/.cache/winetricks

# Only mark the runtime install complete if the key DLLs are actually present.
# This way a transient winetricks/download failure retries on the next update
# instead of being permanently skipped by the marker check above.
SYS32="$WINEPREFIX/drive_c/windows/system32"
if [[ -f "$SYS32/d3dcompiler_47.dll" && -f "$SYS32/vcruntime140.dll" ]]; then
  touch "$MARKER"
fi

exec 6>&-
kill $XVFB_PID

exit 0
