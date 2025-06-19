#!/bin/bash

cd ./starbound/211820/mods

workshopDir="../steamapps/workshop/content/211820"

if [ -d "$workshopDir" ]; then
    echo "Linking mods"

    find "$workshopDir" -maxdepth 1 -mindepth 1 -type d | while read -r modDir; do
        modID=$(basename "$modDir")
        mapfile -t pakFiles < <(find "$modDir" -maxdepth 1 -type f -name '*.pak')

        if [ "${#pakFiles[@]}" -eq 0 ]; then
            echo "No .pak file in $modID, skipping"
            continue
        fi

        for i in "${!pakFiles[@]}"; do
            if [ "$i" -eq 0 ]; then
                ln -sf "${pakFiles[$i]}" "./$modID.pak"
            else
                suffix=$((i+1))
                ln -sf "${pakFiles[$i]}" "./${modID}_$suffix.pak"
            fi
        done
    done
else
    echo "No mods to link"
fi

exit 0
