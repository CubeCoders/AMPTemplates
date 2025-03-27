#!/bin/bash

cd ./openstarbound/server/linux/mods

workshopDir="../../../211820/steamapps/workshop/content/211820"

if [ -d "$workshopDir" ]; then
  echo "Linking mods"

  find "$workshopDir" -maxdepth 1 -mindepth 1 -type d | while read -r modDir; do
    modID=$(basename "$modDir")
    pakFile="$modDir/contents.pak"

    if [ -f "$pakFile" ]; then
      ln -sf "$pakFile" "./$modID.pak"
    else
      echo "No contents.pak in $modID, skipping"
    fi
  done
else
  echo "No mods to link"
fi

exit 0
