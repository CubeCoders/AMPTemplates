#!/bin/bash

# Function to convert a string to hex format
string_to_hex() {
  echo -n "$1" | od -An -tx1 | tr -d ' \n'
}

cd ./arkse/376030

workshop_dir="./steamapps/workshop/content/346110"
mods_install_dir="./ShooterGame/Content/Mods"

if [ ! -d "$workshop_dir" ]; then
  echo "No mods to install"
  exit 0
fi

echo "Installing mods..."

for moddir in "$workshop_dir"/*; do
  modid="$(basename "$moddir")"
  modinfo="$moddir/mod.info"
  modmeta="$moddir/modmeta.info"
  modout="$mods_install_dir/${modid}.mod"

  # Use LinuxNoEditor if it exists, otherwise WindowsNoEditor
  if [ -d "$moddir/LinuxNoEditor" ]; then
    sourcedir="$moddir/LinuxNoEditor"
  elif [ -d "$moddir/WindowsNoEditor" ]; then
    sourcedir="$moddir/WindowsNoEditor"
  else
    echo "Missing platform dir for $modid"
    continue
  fi

  if [ ! -f "$modinfo" ]; then
    echo "Missing mod.info for $modid"
    continue
  fi

  # Read mod.info
  mapnamelen=$(od -An -t u4 -N 4 "$modinfo" | tr -d ' ')
  mapname=$(dd if="$modinfo" bs=1 skip=4 count=$((mapnamelen - 1)) 2>/dev/null)
  num_maps=$(od -An -t u4 -j $((mapnamelen + 4)) -N 4 "$modinfo" | tr -d ' ')
  modname=$(wget -qO- "https://steamcommunity.com/workshop/filedetails/?id=$modid" | \
    sed -n 's/.*<div class="workshopItemTitle">\([^<]*\)<\/div>.*/\1/p' | head -n 1)
  [ -z "$modname" ] && modname="$mapname"
  modpath="../../../ShooterGame/Content/Mods/$modid"

  # Write .mod
  : > "$modout"
  {
    # Replace xxd with string_to_hex
    printf "%s" "$(string_to_hex "$modid")"
    printf "\x00\x00\x00\x00"
    printf "%s" "$(string_to_hex "${#modname}")"
    printf "%s" "$(string_to_hex "$modname")"
    printf "%s" "$(string_to_hex "${#modpath}")"
    printf "%s" "$(string_to_hex "$modpath")"
    printf "%s" "$(string_to_hex "$num_maps")"

    pos=$((mapnamelen + 8))
    for ((i = 0; i < num_maps; i++)); do
      len=$(od -An -t u4 -j $pos -N 4 "$modinfo" | tr -d ' ')
      mapfile=$(dd if="$modinfo" bs=1 skip=$((pos + 4)) count=$len 2>/dev/null)
      printf "%s" "$(string_to_hex "$len")"
      printf "%s" "$(string_to_hex "$mapfile")"
      pos=$((pos + 4 + len))
    done

    # Footer
    printf "%s" "$(string_to_hex '\x33\xFF\x22\xFF\x02\x00\x00\x00\x01')"
  } >> "$modout"

  # Append modmeta or fallback
  if [ -f "$modmeta" ]; then
    cat "$modmeta" >> "$modout"
  else
    printf "%s" "$(string_to_hex '\x01\x00\x00\x00\x08\x00\x00\x00ModType\x00\x02\x00\x00\x001\x00')" >> "$modout"
  fi

  # Create symlink
  target="$mods_install_dir/$modid"
  rm -rf "$target"
  ln -s "$(realpath --relative-to="$mods_install_dir" "$sourcedir")" "$target"

  echo "Installed mod: $modid ($modname)"
done

exit 0
