#!/bin/bash
# Adapted with thanks from https://github.com/mmmaxwwwell/space-engineers-dedicated-docker-linux/blob/main/install-winetricks

cd ./space-engineers-generic
/usr/bin/Xvfb :5 -screen 0 1024x768x16 &
env WINEPREFIX=./.wine WINEARCH=win64 WINEDEBUG=-all ./winetricks corefonts 
env DISPLAY=:5.0 WINEPREFIX=./.wine WINEARCH=win64 WINEDEBUG=-all ./winetricks -q vcrun2017 
env DISPLAY=:5.0 WINEPREFIX=./.wine WINEARCH=win64 WINEDEBUG=-all ./winetricks -q --force dotnet48 
env WINEPREFIX=./.wine WINEARCH=win64 WINEDEBUG=-all ./winetricks sound=disabled 
env DISPLAY=:5.0 WINEPREFIX=./.wine WINEARCH=win64 WINEDEBUG=-all ./winetricks -q vcrun2013 
rm -rf ~/.cache

exit 0