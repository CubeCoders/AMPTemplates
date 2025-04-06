#!/bin/bash

cd ./openstarbound/server/mods

workshopDir="../../211820/steamapps/workshop/content/211820"

if [ -d "$workshopDir" ]; then
  echo "Linking mods"

  find "$workshopDir" -maxdepth 1 -mindepth 1 -type d | while read -r modDir; do
    modID=$(basename "$modDir")
    pakFile=$(find "$modDir" -maxdepth 1 -type f -name '*.pak' | head -n 1)

    if [ -n "$pakFile" ]; then
      ln -sf "$pakFile" "./$modID.pak"
    else
      echo "No .pak file in $modID, skipping"
    fi
  done
else
  echo "No mods to link"
fi

exit 0
