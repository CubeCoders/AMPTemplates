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
command -v perl >/dev/null 2>&1 || { echo >&2 "Error: 'perl' is required but not installed (needed for decompression and .mod generation). Install it."; exit 1; }
perl -MCompress::Raw::Zlib -e 1 >/dev/null 2>&1 || { echo >&2 "Error: Perl module 'Compress::Raw::Zlib' not found. Install it."; exit 1; }

# --- Main Logic ---
workshopContentDir="./arkse/376030/steamapps/workshop/content/346110"
modsInstallDir="./arkse/376030/ShooterGame/Content/Mods"

if [ ! -d "$workshopContentDir" ]; then
  echo "No mods to install."
  exit 0
fi

echo "Installing mods..."

# --- Loop through downloaded mods ---
find "$workshopContentDir" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r modSrcToplevelDir; do

  modId="$(basename "$modSrcToplevelDir")"
  modDestDir="${modsInstallDir}/${modId}"
  mkdir -p "$modDestDir"

  # Determine actual source directory based on branch
  modSrcDir="$modSrcToplevelDir/WindowsNoEditor"
  if [ ! -d "$modSrcDir" ]; then
    # Fallback to top-level if WindowsNoEditor doesn't exist but mod.info does
    if [ -f "$modSrcToplevelDir/mod.info" ]; then
      modSrcDir="$modSrcToplevelDir"
    else
      echo "  Error: Mod source directory not found for branch Windows in $modSrcToplevelDir. Cannot find mod.info. Skipping mod $modId."
      continue
    fi
  # Check if WindowsNoEditor exists but is missing mod.info
  elif [ ! -f "$modSrcDir/mod.info" ]; then
    echo "  Error: Found branch directory $modSrcDir, but it's missing mod.info. Skipping mod $modId."
    continue
  fi

  # --- Sync/Copy Files ---
  # Create necessary sub-directories in destination
  find "$modSrcDir" -mindepth 1 -type d -printf "%P\0" | xargs -0 -I {} -r mkdir -p "$modDestDir/{}"

  # Remove files in destination not present in source
  find "$modDestDir" -type f ! -name '.*' -printf "%P\n" | while IFS= read -r f; do
    if [ ! -f "$modSrcDir/$f" ] && [ ! -f "$modSrcDir/${f}.z" ]; then
      rm -f "$modDestDir/$f"
    fi
  done

  # Remove empty directories in destination
  find "$modDestDir" -mindepth 1 -depth -type d -empty -print -delete

  # Copy/link regular files (using reflink primarily)
  find "$modSrcDir" -type f ! \( -name '*.z' -or -name '*.z.uncompressed_size' \) -printf "%P\n" | while IFS= read -r f; do
    src_file="$modSrcDir/$f"
    dest_file="$modDestDir/$f"
    # Check if dest doesn't exist or source is newer
    if [ ! -f "$dest_file" ] || [ "$src_file" -nt "$dest_file" ]; then
      mkdir -p "$(dirname "$dest_file")"
      # Attempt reflink, fall back to standard copy within cp if needed
      # Assumes source/dest are on the same device (no explicit check)
      cp --reflink=auto -p "$src_file" "$dest_file"
    fi
  done

  # Decompress .z files
  find "$modSrcDir" -type f -name '*.z' -printf "%P\n" | while IFS= read -r f; do
    src_file="$modSrcDir/$f"
    dest_file="$modDestDir/${f%.z}"
    # Check if dest doesn't exist or source is newer
    if [ ! -f "$dest_file" ] || [ "$src_file" -nt "$dest_file" ]; then
      mkdir -p "$(dirname "$dest_file")"
      # Decompress using Perl
      if perl -M'Compress::Raw::Zlib' -e '
          # (Perl decompression code unchanged)
          my $infile = $ARGV[0]; my $outfile = $ARGV[1];
          open(IN, "<", $infile) or die "Cannot open input $infile: $!"; binmode IN;
          my $sig; read(IN, $sig, 8) == 8 or die "Unable to read signature from $infile: $!";
          if ($sig ne "\xC1\x83\x2A\x9E\x00\x00\x00\x00") { die "Bad file magic in $infile"; }
          my $header; read(IN, $header, 24) == 24 or die "Unable to read header from $infile: $!";
          my ($cl, $ch, $ctl, $cth, $utl, $uth) = unpack("(L<L<L<L<L<L<)", $header);
          my @chunks = (); my $cu = 0;
          while ($cu < $ctl) {
              my $chdr; read(IN, $chdr, 16) == 16 or die "Unable to read chunk header from $infile: $!";
              my ($csl, $csh, $usl, $ush) = unpack("(L<L<L<L<)", $chdr);
              push @chunks, $csl; $cu += $csl;
          }
          open(OUT, ">", $outfile) or die "Cannot open output $outfile: $!"; binmode OUT;
          foreach my $cs (@chunks) {
              my $d; read(IN, $d, $cs) == $cs or die "File read failed for chunk in $infile: $!";
              my ($inf, $st) = new Compress::Raw::Zlib::Inflate(); my $o;
              $st = $inf->inflate($d, $o, 1);
              if ($st != Z_OK && $st != Z_STREAM_END) { die "Decompression error in $infile; status: $st"; }
              print OUT $o;
          }
          close IN; close OUT; exit 0;
      ' "$src_file" "$dest_file"; then
        # If successful, match timestamp
        touch -c -r "$src_file" "$dest_file"
      else
        # If failed, remove potentially incomplete output file
        rm -f "$dest_file"
      fi
    fi
  done

  # --- Generate .mod File ---
  modOutputFile="${modsInstallDir}/${modId}.mod"

  modInfoFile="$modSrcDir/mod.info"
  if [ ! -f "$modInfoFile" ]; then
    echo "  Error: $modInfoFile not found! Cannot generate .mod file. Skipping mod $modId."
    continue
  fi

  # Fetch mod name from Steam Community using wget
  modName=""
  modNameRaw=""
  # Use subshell to avoid potential variable conflicts if wget/sed fail badly
  modNameRaw=$(wget -qO- "http://steamcommunity.com/sharedfiles/filedetails/?id=${modId}" | sed -n 's|^.*<div class="workshopItemTitle">\([^<]*\)</div>.*|\1|p' | head -n 1)
  # Trim whitespace
  modName=$(echo "$modNameRaw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Use Perl to read mod.info and write .mod file
  if perl -e '
      use strict; use warnings;
      # Args: arkserverdir_rel, modId_str, modName_fetched (ignored), mod_info_path, output_mod_path
      my ($arkserverdir_rel, $modId_str, $modName_fetched, $mod_info_path, $output_mod_path) = @ARGV;

      open(my $fh_in, "<:raw", $mod_info_path) or die "Cannot open mod.info $mod_info_path: $!";
      my $data; { local $/; $data = <$fh_in>; } close $fh_in;

      # Read metadata needed from mod.info
      my $mapnamelen = unpack("L<", substr($data, 0, 4));
      my $nummaps_offset = 4 + $mapnamelen;
      my $nummaps = unpack("L<", substr($data, $nummaps_offset, 4));

      # Construct the Mod Path string
      my $modpath = "../../../" . $arkserverdir_rel . "/Content/Mods/" . $modId_str . "\x00";
      my $modpathlen = length($modpath);

      # Pack the Mod ID
      my $modId_packed = pack("L<", int($modId_str));

      open(my $fh_out, ">:raw", $output_mod_path) or die "Cannot open output .mod file $output_mod_path: $!";

      # --- Write Header in Correct Order with BOTH padding fields ---
      print $fh_out $modId_packed;                  # Mod ID (uint32)
      print $fh_out pack("L<", 0);                  # Padding1 (uint32 = 0)
      print $fh_out pack("L<", 0);                  # Padding2 (uint32 = 0) # ADDED MISSING PADDING
      print $fh_out pack("L<", $modpathlen);        # Length of Mod Path (uint32)
      print $fh_out $modpath;                       # Mod Path String (null-terminated)
      print $fh_out pack("L<", $nummaps);           # Number of Maps (uint32)
      # --- End Header ---

      # --- Write Map Entries (Corrected null handling) ---
      my $pos = $nummaps_offset + 4; # Position after num maps field in mod.info
      for (my $i = 0; $i < $nummaps; $i++) {
          # Read map file length - Assume this length INCLUDES the null terminator from mod.info
          my $mapfilelen = unpack("L<", substr($data, $pos, 4));
          # Read exactly mapfilelen bytes
          my $mapfile = $mapfilelen > 0 ? substr($data, $pos + 4, $mapfilelen) : "";
          # Use mapfilelen directly as the packed length. DO NOT add extra null.
          my $mapfilepackedlen = $mapfilelen;

          print $fh_out pack("L<", $mapfilepackedlen);  # Map File Length (including null from source)
          print $fh_out $mapfile;                       # Map File Name (including null from source)

          $pos += (4 + $mapfilelen); # Advance position in mod.info data
      }
      # --- End Map Entries ---

      # --- Write Footer ---
      print $fh_out "\x33\xFF\x22\xFF\x02\x00\x00\x00\x01";

      close $fh_out;
      exit 0; # Success
    ' "ShooterGame" "$modId" "$modName" "$modInfoFile" "$modOutputFile"; then

    # Append modmeta.info if it exists, otherwise append default footer
    modmetaFile="$modSrcDir/modmeta.info"
    if [ -f "$modmetaFile" ]; then
      cat "$modmetaFile" >> "$modOutputFile"
    else
      # Default ModType footer (Type 1), append directly as binary
      printf '\x01\x00\x00\x00\x08\x00\x00\x00ModType\x00\x02\x00\x00\x001\x00' >> "$modOutputFile"
    fi

     # Set timestamp of .mod file to match the mod.info file
     touch -c -r "$modInfoFile" "$modOutputFile"
  else
    # Handle failure of Perl script to generate .mod file
    echo "  Error: Failed to generate .mod file for $modId using Perl. Skipping."
    rm -f "$modOutputFile" # Clean up potentially empty/partial file
    continue
  fi

done # End of loop through mod directories

echo "Mod installation process finished."
exit 0