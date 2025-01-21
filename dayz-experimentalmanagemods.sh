#!/bin/bash

ModDirFormat="$1"

cd ./dayz/1042420

if [ -d ./steamapps/workshop/content/221100 ]; then
  find ./steamapps/workshop/content/221100/ -depth -name "*[A-Z]*" -print0 |\
  xargs -0 -I {} bash -c "mv \"{}\" \"\$(echo \"{}\" | sed 's,\(.*\)\/\(.*\),\1\/\L\2,')\"" >/dev/null 2>&1

  if [ "$ModDirFormat" = "false" ]; then
    find ./steamapps/workshop/content/221100 -maxdepth 1 -mindepth 1 -type d | while read -r mod_dir; do
      mod_name=$(grep -oP '^\s*name\s*=\s*"\K[^"]+' "$mod_dir/mod.cpp")
      rm -f "./@$mod_name" >/dev/null 2>&1
    done
  else
    find ./steamapps/workshop/content/221100 -maxdepth 1 -mindepth 1 -type d | while read -r mod_dir; do
      mod_name=$(grep -oP '^\s*name\s*=\s*"\K[^"]+' "$mod_dir/mod.cpp")
      rm -f "./$(basename "$mod_dir")" >/dev/null 2>&1
      ln -sf "$mod_dir" "./@$mod_name"
    done
  fi
fi

exit 0