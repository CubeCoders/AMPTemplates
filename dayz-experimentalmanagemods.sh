#!/bin/bash

ModDirFormat="$1"

cd ./dayz/1042420

if [ -d ./steamapps/workshop/content/221100 ]; then
  # Convert uppercase filenames to lowercase
  find ./steamapps/workshop/content/221100/ -depth -name "*[A-Z]*" -print0 |\
  xargs -0 -I {} bash -c "mv \"{}\" \"\$(echo \"{}\" | sed 's,\(.*\)\/\(.*\),\1\/\L\2,')\"" >/dev/null 2>&1

  if [ "$ModDirFormat" = "false" ]; then
    # Remove symlinks corresponding to actual directories
    find ./steamapps/workshop/content/221100 -maxdepth 1 -mindepth 1 -type d | while read -r mod_dir; do
      mod_name=$(grep -oP '^\s*name\s*=\s*"\K[^"]+' "$mod_dir/meta.cpp")
      rm -f "./@$mod_name"  # Remove the symlink corresponding to the directory
    done
    # Create traditional symlinks for numbered directories
    find ./steamapps/workshop/content/221100 -maxdepth 1 -mindepth 1 -type d -exec ln -sf {} ./ \;
  else
    # Remove numbered symlinks corresponding to the directories
    find ./steamapps/workshop/content/221100 -maxdepth 1 -mindepth 1 -type d | while read -r mod_dir; do
      rm -f "./$(basename "$mod_dir")"  # Remove the symlink corresponding to the directory
    done
    # Create @name symlinks for directories based on mod.cpp
    find ./steamapps/workshop/content/221100 -maxdepth 1 -mindepth 1 -type d | while read -r mod_dir; do
      mod_name=$(grep -oP '^\s*name\s*=\s*"\K[^"]+' "$mod_dir/meta.cpp")
      ln -sf "$mod_dir" "./@$mod_name"
    done
  fi
fi

exit 0