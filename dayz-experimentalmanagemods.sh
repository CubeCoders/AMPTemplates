#!/bin/bash

ModDirFormat="$1"

cd ./dayz/1042420

workshopDir="./steamapps/workshop/content/221100"

if [ -d $workshopDir ]; then
  # Convert uppercase filenames to lowercase
  find $workshopDir/ -depth -name "*[A-Z]*" -print0 |\
  xargs -0 -I {} bash -c "mv \"{}\" \"\$(echo \"{}\" | sed 's,\(.*\)\/\(.*\),\1\/\L\2,')\"" >/dev/null 2>&1

  if [ "$ModDirFormat" = "false" ]; then
    # Remove @name symlinks corresponding to the mod directories based on meta.cpp
    find $workshopDir -maxdepth 1 -mindepth 1 -type d | while read -r modDir; do
      modName=$(sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"\([^"]\+\)".*/\1/p' "$modDir/meta.cpp")
      [[ -n "$modName" ]] && rm -f "./@$modName" >/dev/null 2>&1
      # Create numbered symlinks for the mod directories
      ln -sf $modDir ./
    done
  else
    # Remove numbered symlinks for the mod directories
    find $workshopDir -maxdepth 1 -mindepth 1 -type d | while read -r modDir; do
      rm -f "./$(basename "$modDir")" >/dev/null 2>&1
      # Create @name symlinks corresponding to the mod directories based on meta.cpp
      modName=$(sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"\([^"]\+\)".*/\1/p' "$modDir/meta.cpp")
      [[ -n "$modName" ]] && ln -sfT $modDir "@$modName"
    done
  fi
fi

exit 0