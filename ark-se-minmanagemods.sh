#!/bin/bash
# 
# Adapted from, and with credit to, https://github.com/arkmanager/ark-server-tools/blob/master/tools/arkmanager
#
# The MIT License (MIT)
#
# Copyright (c) 2015 Fez Vrasta
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# --- Dependency Checks ---
command -v perl >/dev/null 2>&1 || { echo >&2 "Error: Executable 'perl' is not installed. Please install it."; exit 1; }
perl -MCompress::Raw::Zlib -e 1 >/dev/null 2>&1 || { echo >&2 "Error: Perl module 'Compress::Raw::Zlib' not found. Please install it."; exit 1; }

# --- Variables ---
workshopContentDir="./376030/steamapps/workshop/content/346110"
modsInstallDir="./376030/ShooterGame/Content/Mods"
modIds=()

# Function to install a mod with retry on timeout
downloadMod() {
  local modId="$1"
  local maxRetries=5
  local attempt=0
  local output

  while (( attempt < maxRetries )); do
    ((attempt++))
    echo "Downloading mod $modId"
    
    output=$(./steamcmd.sh +force_install_dir 376030 +login anonymous +workshop_download_item 346110 "$modId" validate +quit 2>&1)

    # Check success
    if echo "$output" | grep -q "Success. Downloaded item $modId"; then
      echo "Mod $modId downloaded successfully"
      return 0
    fi

    echo "Download failed for mod $modId. Retrying..."
    sleep 2
  done

  echo "Mod $modId failed after $maxRetries attempts"
  return 1
}

# Function to extract and install downloaded mod files
installMod() {
  local modId="$1"
  local modDestDir="${modsInstallDir}/${modId}"
  local modSrcToplevelDir="${workshopContentDir}/${modId}"
  local modSrcDir
  local modOutputFile
  local modInfoFile
  local modmetaFile
  local modName
  local srcFile
  local destFile
  
  
  mkdir -p "$modDestDir"

  # Determine actual source directory based on branch
  modSrcDir="$modSrcToplevelDir/WindowsNoEditor"
  if [ ! -d "$modSrcDir" ]; then
    if [ -f "$modSrcToplevelDir/mod.info" ]; then
      modSrcDir="$modSrcToplevelDir"
    else
      echo "  Error: Mod source directory not found for branch Windows in $modSrcToplevelDir. Cannot find mod.info. Skipping mod $modId."
      return
    fi
  elif [ ! -f "$modSrcDir/mod.info" ]; then
    echo "  Error: Found branch directory $modSrcDir, but it's missing mod.info. Skipping mod $modId."
    return
  fi

  # Create necessary sub-directories in destination
  find "$modSrcDir" -type d -printf "$modDestDir/%P\0" | xargs -0 -r mkdir -p

  # Remove files in destination not present in source
  find "$modDestDir" -type f ! -name '.*' -printf "%P\n" | while read -r f; do
    if [ ! -f "$modSrcDir/$f" ] && [ ! -f "$modSrcDir/${f}.z" ]; then
      rm -f "$modDestDir/$f"
    fi
  done

  # Remove empty directories in destination
  find "$modDestDir" -depth -type d -printf "%P\n" | while read -r d; do
    if [ ! -d "$modSrcDir/$d" ]; then
      rmdir "$modDestDir/$d"
    fi
  done

  # Copy/link regular files (using reflink primarily)
  find "$modSrcDir" -type f ! \( -name '*.z' -or -name '*.z.uncompressed_size' \) -printf "%P\n" | while read -r f; do
    srcFile="$modSrcDir/$f"
    destFile="$modDestDir/$f"
    if [ ! -f "$destFile" ] || [ "$srcFile" -nt "$destFile" ]; then
      cp --reflink=auto -p "$srcFile" "$destFile"
    fi
  done

  # Decompress .z files
  find "$modSrcDir" -type f -name '*.z' -printf "%P\n" | while read -r f; do
    srcFile="$modSrcDir/$f"
    destFile="$modDestDir/${f%.z}"
    if [ ! -f "$destFile" ] || [ "$srcFile" -nt "$destFile" ]; then
      perl -M'Compress::Raw::Zlib' -e '
        my $sig;
        read(STDIN, $sig, 8) or die "Unable to read compressed file: $!";
        if ($sig != "\xC1\x83\x2A\x9E\x00\x00\x00\x00"){
          die "Bad file magic";
        }
        my $data;
        read(STDIN, $data, 24) or die "Unable to read compressed file: $!";
        my ($chunksizelo, $chunksizehi,
            $comprtotlo,  $comprtothi,
            $uncomtotlo,  $uncomtothi)  = unpack("(LLLLLL)<", $data);
        my @chunks = ();
        my $comprused = 0;
        while ($comprused < $comprtotlo) {
          read(STDIN, $data, 16) or die "Unable to read compressed file: $!";
          my ($comprsizelo, $comprsizehi,
              $uncomsizelo, $uncomsizehi) = unpack("(LLLL)<", $data);
          push @chunks, $comprsizelo;
          $comprused += $comprsizelo;
        }
        foreach my $comprsize (@chunks) {
          read(STDIN, $data, $comprsize) or die "File read failed: $!";
          my ($inflate, $status) = new Compress::Raw::Zlib::Inflate();
          my $output;
          $status = $inflate->inflate($data, $output, 1);
          if ($status != Z_STREAM_END) {
            die "Bad compressed stream; status: " . ($status);
          }
          if (length($data) != 0) {
            die "Unconsumed data in input"
          }
          print $output;
        }
      ' < "$srcFile" > "$destFile"
      touch -c -r "$srcFile" "$destFile"
    fi
  done

  # --- Generate .mod File ---
  modOutputFile="${modsInstallDir}/${modId}.mod"

  modInfoFile="$modSrcDir/mod.info"
  if [ ! -f "$modInfoFile" ]; then
    echo "  Error: $modInfoFile not found! Cannot generate .mod file. Skipping mod $modId."
    continue
  fi

  # Fetch mod name from Steam Community
  modName=$(wget -qO- "http://steamcommunity.com/sharedfiles/filedetails/?id=${modId}" | sed -n 's|^.*<div class="workshopItemTitle">\([^<]*\)</div>.*|\1|p' | head -n 1)
  
  # Use Perl to read mod.info and write .mod file
  perl -e '
    my $data;
    { local $/; $data = <STDIN>; }
    my $mapnamelen = unpack("@0 L<", $data);
    my $mapname = substr($data, 4, $mapnamelen - 1);
    my $nummaps = unpack("@" . ($mapnamelen + 4) . " L<", $data);
    my $pos = $mapnamelen + 8;
    my $modname = ($ARGV[2] || $mapname) . "\x00";
    my $modnamelen = length($modname);
    my $modpath = "../../../" . $ARGV[0] . "/Content/Mods/" . $ARGV[1] . "\x00";
    my $modpathlen = length($modpath);
    print pack("L< L< L< Z$modnamelen L< Z$modpathlen L<",
      $ARGV[1], 0, $modnamelen, $modname, $modpathlen, $modpath,
      $nummaps);
    for (my $mapnum = 0; $mapnum < $nummaps; $mapnum++){
      my $mapfilelen = unpack("@" . ($pos) . " L<", $data);
      my $mapfile = substr($data, $mapnamelen + 12, $mapfilelen);
      print pack("L< Z$mapfilelen", $mapfilelen, $mapfile);
      $pos = $pos + 4 + $mapfilelen;
    }
    print "\x33\xFF\x22\xFF\x02\x00\x00\x00\x01";
  ' "ShooterGame" "$modId" "$modName" < "$modInfoFile" > "$modOutputFile"

  # Append modmeta.info if it exists, otherwise append default footer
  modmetaFile="$modSrcDir/modmeta.info"
  if [ -f "$modmetaFile" ]; then
    cat "$modmetaFile" >> "$modOutputFile"
  else
    printf '\x01\x00\x00\x00\x08\x00\x00\x00ModType\x00\x02\x00\x00\x001\x00' >> "$modOutputFile"
  fi

  # Set timestamp of .mod file to match the mod.info file
  touch -c -r "$modInfoFile" "$modOutputFile"
}

# --- Main Loop ---
if [ -z "$1" ]; then
  echo "No mod IDs specified"
  exit 1
fi

echo "Installing/updating mods..."

modIds=$(echo "$1" | sed 's/^"\(.*\)"$/\1/')
IFS=',' read -ra modIdArray <<< "$modIds"
cd ./arkse

for modId in "${modIdArray[@]}"; do
  if downloadMod "$modId"; then
    installMod "$modId"
  fi
done

echo "Mod installation/update process finished."
exit 0
