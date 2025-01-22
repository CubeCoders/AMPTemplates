#!/bin/bash

ModDirFormat="$1"

cd ./arma3/233780

workshopDir="./steamapps/workshop/content/107410"

if [ -d $workshopDir ]; then
  echo "Managing mods"
  # Convert uppercase filenames to lowercase
  find $workshopDir/ -depth -name "*[A-Z]*" -print0 | \
    xargs -0 -I {} bash -c "mv \"{}\" \"\$(echo \"{}\" | sed 's,\(.*\)\/\(.*\),\1\/\L\2,')\"" >/dev/null 2>&1

  find $workshopDir -maxdepth 1 -mindepth 1 -type d | while read -r modDir; do
    # Extract modName from meta.cpp
    modName=$(sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"\([^"]\+\)".*/\1/p' "$modDir/meta.cpp")

    if [ "$ModDirFormat" = "false" ]; then
      # Remove @name symlinks corresponding to the mod directories based on meta.cpp
      [[ -n "$modName" ]] && rm -f "./@$modName" >/dev/null 2>&1
      # Create numbered symlinks for the mod directories
      ln -sf "$modDir" ./
    else
      # Remove numbered symlinks for the mod directories
      rm -f "./$(basename "$modDir")" >/dev/null 2>&1
      # Create @name symlinks corresponding to the mod directories based on meta.cpp
      [[ -n "$modName" ]] && ln -sfT "$modDir" "@$modName"
    fi
  done
else
  echo "No mods to manage"
fi

exit 0