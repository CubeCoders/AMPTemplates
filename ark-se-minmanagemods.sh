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
command -v perl >/dev/null 2>&1 || { echo >&2 "Executable 'perl' is not installed. Please install it."; exit 1; }
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

  # --- Sync/Copy Files (Excluding .z*) ---
  try {
    if (Test-Path -LiteralPath $modDestDir) {
      Remove-Item -LiteralPath $modDestDir -Recurse -Force -ErrorAction Stop
    }
    Copy-Item -LiteralPath $modSrcDir -Destination $modDestDir -Recurse -Force -Exclude '*.z', '*.z.uncompressed_size' -ErrorAction Stop
  } catch {
    Write-Host "  Error copying files for mod $modId from $modSrcDir to $modDestDir. Error: $($_.Exception.Message). Skipping mod $modId."
    return
  }

  # --- Decompress .z files (using Perl, Source -> Destination) ---
  $zFiles = Get-ChildItem -Path $modSrcDir -Recurse -Filter *.z -ErrorAction SilentlyContinue
  if ($zFiles) {
    $perlDecompressScript = 'use strict; use warnings; use File::Basename; use File::Copy; use Compress::Raw::Zlib; my ($infile, $outfile) = @ARGV; my $tempoutfile = $outfile . ".tmpperl$$"; open(IN, "<:raw", $infile) or die "Cannot open input $infile: $!"; my $sig; read(IN, $sig, 8) == 8 or die "Unable to read signature from $infile: $!"; if ($sig ne "\xC1\x83\x2A\x9E\x00\x00\x00\x00") { die "Bad file magic in $infile"; } my $header; read(IN, $header, 24) == 24 or die "Unable to read header from $infile: $!"; my ($cl, $ch, $ctl, $cth, $utl, $uth) = unpack("(L<L<L<L<L<L<)", $header); my @chunks = (); my $cu = 0; while ($cu < $ctl) { my $chdr; read(IN, $chdr, 16) == 16 or die "Unable to read chunk header from $infile: $!"; my ($csl, $csh, $usl, $ush) = unpack("(L<L<L<L<)", $chdr); push @chunks, $csl; $cu += $csl; } use File::Path qw(make_path); my $outdir = dirname($tempoutfile); unless (-d $outdir) { make_path($outdir) or die "Cannot create directory $outdir: $!"; } open(OUT, ">:raw", $tempoutfile) or die "Cannot open output $tempoutfile: $!"; foreach my $cs (@chunks) { my $d; read(IN, $d, $cs) == $cs or die "File read failed for chunk in $infile: $!"; my ($inf, $st) = new Compress::Raw::Zlib::Inflate(); my $o; $st = $inf->inflate($d, $o, 1); if ($st != Z_OK && $st != Z_STREAM_END) { die "Decompression error in $infile; status: $st"; } print OUT $o; } close IN; close OUT; unless (rename($tempoutfile, $outfile)) { unlink $tempoutfile; die "Failed to rename $tempoutfile to $outfile: $!"; } exit 0;'

    foreach ($zFileItem in $zFiles) {
      # Source path is the .z file found
      $zSrcFile = $zFileItem.FullName
      # Calculate the relative path within the mod structure
      $relativeZPath = $zFileItem.FullName.Substring($modSrcDir.Length)
      # Calculate the final destination path for the DECOMPRESSED file
      $zDestFile = Join-Path -Path $modDestDir -ChildPath ($relativeZPath -replace '\.z$')

      # Check timestamp against DESTINATION path
      if (-not (Test-Path -LiteralPath $zDestFile) -or ($zFileItem.LastWriteTimeUtc -gt (Get-Item -LiteralPath $zDestFile -ErrorAction SilentlyContinue).LastWriteTimeUtc)) {
        $destDirForFile = Split-Path $zDestFile -Parent
        if (-not (Test-Path -LiteralPath $destDirForFile)) {
           New-Item -ItemType Directory -Path $destDirForFile -Force -ErrorAction SilentlyContinue | Out-Null
        }

        & $perlPath.Path -e $perlDecompressScript $zSrcFile $zDestFile 2>$null
        if ($?) {
          # Set timestamp on the DESTINATION file
          (Get-Item -LiteralPath $zDestFile).LastWriteTimeUtc = $zFileItem.LastWriteTimeUtc
        } else {
          if (Test-Path -LiteralPath $zDestFile) { Remove-Item -LiteralPath $zDestFile -Force -ErrorAction SilentlyContinue }
        }
      }
      # else: Destination exists and is up-to-date, do nothing with source .z file
    }
  }

  # --- Generate .mod File ---
  modOutputFile="${modsInstallDir}/${modId}.mod"

  modInfoFile="$modSrcDir/mod.info"
  if [ ! -f "$modInfoFile" ]; then
    echo "  Error: $modInfoFile not found! Cannot generate .mod file. Skipping mod $modId."
    continue
  fi

  # Fetch mod name from Steam Community
  modName=""
  modNameRaw=""
  modNameRaw=$(wget -qO- "http://steamcommunity.com/sharedfiles/filedetails/?id=${modId}" | sed -n 's|^.*<div class="workshopItemTitle">\([^<]*\)</div>.*|\1|p' | head -n 1)
  # Trim whitespace
  modName=$(echo "$modNameRaw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Use Perl to read mod.info and write .mod file
  if perl -e '
    use strict; use warnings;
    # Args: arkserverdir_rel, modId_str, modName_fetched, mod_info_path, output_mod_path
    my ($arkserverdir_rel, $modId_str, $modName_fetched, $mod_info_path, $output_mod_path) = @ARGV;

    open(my $fh_in, "<:raw", $mod_info_path) or die "Cannot open mod.info $mod_info_path: $!";
    my $data; { local $/; $data = <$fh_in>; } close $fh_in;

    my $mapnamelen = unpack("L<", substr($data, 0, 4));
    my $mapname = $mapnamelen > 0 ? substr($data, 4, $mapnamelen - 1) : ""; # Assuming length includes null
    my $nummaps_offset = 4 + $mapnamelen;
    my $nummaps = unpack("L<", substr($data, $nummaps_offset, 4));
    my $pos = $nummaps_offset + 4; # Position after num maps field

    my $modname = ($modName_fetched || $mapname); # Use fetched name or mapname
    $modname .= "\x00"; my $modnamelen = length($modname);

    my $modpath = "../../../" . $arkserverdir_rel . "/Content/Mods/" . $modId_str . "\x00";
    my $modpathlen = length($modpath);

    my $modid_packed = pack("L<", int($modId_str));

    open(my $fh_out, ">:raw", $output_mod_path) or die "Cannot open output .mod file $output_mod_path: $!";

    print $fh_out $modid_packed;                  # Mod ID (uint32)
    print $fh_out pack("L<", 0);                  # Padding (uint32)
    print $fh_out pack("L<", $modnamelen);        # Mod Name Length (uint32)
    print $fh_out $modname;                       # Mod Name String (null-terminated)
    print $fh_out pack("L<", $modpathlen);        # Mod Path Length (uint32)
    print $fh_out $modpath;                       # Mod Path String (null-terminated)
    print $fh_out pack("L<", $nummaps);           # Number of Maps (uint32)

    my $map_read_pos = $pos; # Use the calculated position for reading maps
    for (my $mapnum = 0; $mapnum < $nummaps; $mapnum++){
        my $mapfilelen = unpack("@" . ($map_read_pos) . " L<", $data); # Read length at current position
        my $mapfile = $mapfilelen > 0 ? substr($data, $map_read_pos + 4, $mapfilelen) : "";
        my $mapfilepackedlen = $mapfilelen; # Use length directly

        print $fh_out pack("L<", $mapfilepackedlen); # Print length
        print $fh_out $mapfile;                      # Print name (including null from source)

        $map_read_pos += (4 + $mapfilelen); # Advance position correctly
    }

    print $fh_out "\x33\xFF\x22\xFF\x02\x00\x00\x00\x01"; # Footer (Note: uses 0x01 ending)

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

done

echo "Mod installation process finished."
exit 0