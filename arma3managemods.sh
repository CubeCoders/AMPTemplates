#!/bin/bash

ModDirFormat="$1"

cd ./arma3/233780

workshopDir="./steamapps/workshop/content/107410"

if [ -d "$workshopDir" ]; then
  echo "Converting and linking mods"

  # Convert uppercase filenames to lowercase
  find "$workshopDir/" -depth -name "*[A-Z]*" -print0 | \
    xargs -0 -I {} bash -c "mv \"{}\" \"\$(echo \"{}\" | sed 's,\(.*\)\/\(.*\),\1\/\L\2,')\"" >/dev/null 2>&1

  find "$workshopDir" -maxdepth 1 -mindepth 1 -type d | while read -r modDir; do
    modName=""

    # Extract modName from meta.cpp
    metaCppPath="$modDir/meta.cpp"
    if [ -f "$metaCppPath" ]; then
      modName=$(sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"\([^"]\+\)".*/\1/p' "$metaCppPath")
    fi

    if [ -z "$modName" ]; then
      # Fallback: Try mod.cpp if meta.cpp does not contain a name
      modCppPath="$modDir/mod.cpp"
      if [ -f "$modCppPath" ]; then
        modName=$(sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"\([^"]\+\)".*/\1/p' "$modCppPath")
      fi

      if [ -z "$modName" ]; then
        # Final fallback: Try fetching name from Steam workshop webpage if no name found
        modID=$(basename "$modDir")
        modName=$(wget -qO- "https://steamcommunity.com/workshop/filedetails/?id=$modID" | \
          sed -n 's/.*<div class="workshopItemTitle">\([^<]*\)<\/div>.*/\1/p' | head -n 1)

        if [ -z "$modName" ]; then
          echo "Error: Unable to retrieve name for workshop item $modID. Skipping"
          continue
        fi
      fi
    fi

    # Sanitise modName
    modName=$(echo "$modName" | tr '/' '-' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ "$ModDirFormat" = "false" ]; then
      # Remove @name symlinks
      rm -f "./@$modName" >/dev/null 2>&1

      # Create numbered symlinks
      ln -sf "$modDir" ./
    else
      # Remove numbered symlinks
      rm -f "./$(basename "$modDir")" >/dev/null 2>&1

      # Create @name symlink
      ln -sfT "$modDir" "./@$modName"
    fi
  done
else
  echo "No mods to convert and link"
fi

exit 0