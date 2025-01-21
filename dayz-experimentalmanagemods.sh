#!/bin/bash

ModDirFormat="$1"

cd ./dayz/1042420

if [ -d ./steamapps/workshop/content/221100 ]; then
  # Convert uppercase filenames to lowercase
  find ./steamapps/workshop/content/221100/ -depth -name "*[A-Z]*" -print0 |\
  xargs -0 -I {} bash -c "mv \"{}\" \"\$(echo \"{}\" | sed 's,\(.*\)\/\(.*\),\1\/\L\2,')\"" >/dev/null 2>&1

  if [ "$ModDirFormat" = "false" ]; then
    # Remove @name symlinks corresponding to mod directories based on meta.cpp
    find ./steamapps/workshop/content/221100 -maxdepth 1 -mindepth 1 -type d | while read -r mod_dir; do
      mod_name=$(sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"\([^"]\+\)".*/\1/p' "$mod_dir/meta.cpp")
      [[ -n "$mod_name" ]] && rm -f "./@$mod_name" >/dev/null 2>&1
    done
    # Create numbered symlinks for mod directories
    find ./steamapps/workshop/content/221100 -maxdepth 1 -mindepth 1 -type d -exec ln -sf {} ./ \;
  else
    # Remove numbered symlinks for mod directories
    find ./steamapps/workshop/content/221100 -maxdepth 1 -mindepth 1 -type d | while read -r mod_dir; do
      rm -f "./$(basename "$mod_dir")" >/dev/null 2>&1
    done
    # Create @name symlinks corresponding to mod directories based on meta.cpp
    find ./steamapps/workshop/content/221100 -maxdepth 1 -mindepth 1 -type d | while read -r mod_dir; do
      mod_name=$(sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"\([^"]\+\)".*/\1/p' "$mod_dir/meta.cpp")
      [[ -n "$mod_name" ]] && ln -sfT "$mod_dir" "@$mod_name"
    done
  fi
fi

exit 0