#!/bin/bash

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
    printf "\\x%02x\\x%02x\\x%02x\\x%02x" $((modid & 0xFF)) $(((modid >> 8) & 0xFF)) $(((modid >> 16) & 0xFF)) $(((modid >> 24) & 0xFF))
    printf "\x00\x00\x00\x00"
    printf "\\x%02x\\x%02x\\x%02x\\x%02x" $(( (${#modname} + 1) & 0xFF)) $(((${#modname} + 1 >> 8) & 0xFF)) 0 0
    printf "%s\x00" "$modname"
    printf "\\x%02x\\x%02x\\x%02x\\x%02x" $(( (${#modpath} + 1) & 0xFF)) $(((${#modpath} + 1 >> 8) & 0xFF)) 0 0
    printf "%s\x00" "$modpath"
    printf "\\x%02x\\x%02x\\x%02x\\x%02x" $((num_maps & 0xFF)) $(((num_maps >> 8) & 0xFF)) $(((num_maps >> 16) & 0xFF)) $(((num_maps >> 24) & 0xFF))

    pos=$((mapnamelen + 8))
    for ((i = 0; i < num_maps; i++)); do
      len=$(od -An -t u4 -j $pos -N 4 "$modinfo" | tr -d ' ')
      mapfile=$(dd if="$modinfo" bs=1 skip=$((pos + 4)) count=$len 2>/dev/null)
      printf "\\x%02x\\x%02x\\x%02x\\x%02x" $((len & 0xFF)) $(((len >> 8) & 0xFF)) $(((len >> 16) & 0xFF)) $(((len >> 24) & 0xFF))
      printf "%s" "$mapfile"
      pos=$((pos + 4 + len))
    done

    # Footer
    printf '\x33\xFF\x22\xFF\x02\x00\x00\x00\x01'
  } >> "$modout"

  # Append modmeta or fallback
  if [ -f "$modmeta" ]; then
    cat "$modmeta" >> "$modout"
  else
    printf '\x01\x00\x00\x00\x08\x00\x00\x00ModType\x00\x02\x00\x00\x001\x00' >> "$modout"
  fi

  # Create symlink
  target="$mods_install_dir/$modid"
  rm -rf "$target"
  ln -s "$(realpath --relative-to="$mods_install_dir" "$sourcedir")" "$target"

  echo "Installed mod: $modid ($modname)"
done

exit 0
