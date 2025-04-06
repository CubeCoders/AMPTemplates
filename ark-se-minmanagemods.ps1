#Requires -Version 5.1

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
$perlPath = Get-Command perl -ErrorAction SilentlyContinue
if (-not $perlPath) {
  Write-Error "Executable 'perl' not found in PATH. Please install Perl, ideally from https://strawberryperl.com/."
  exit 1
}

# --- Main Logic ---
$basePath = $PSScriptRoot
$arkInstancePath = Join-Path -Path $basePath -ChildPath "arkse\376030"
$workshopContentDir = Join-Path -Path $arkInstancePath -ChildPath "steamapps\workshop\content\346110"
$modsInstallDir = Join-Path -Path $arkInstancePath -ChildPath "ShooterGame\Content\Mods"

if (-not (Test-Path -LiteralPath $workshopContentDir -PathType Container)) {
  Write-Host "No mods to install."
  exit 0
}

Write-Host "Installing mods..."

# Ensure the base mods installation directory exists
if (-not (Test-Path -LiteralPath $modsInstallDir -PathType Container)) {
  New-Item -Path $modsInstallDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

# --- Loop through downloaded mods ---
Get-ChildItem -Path $workshopContentDir -Directory | ForEach-Object {
  $modSrcToplevelDir = $_
  $modId = $modSrcToplevelDir.Name
  $modDestDir = Join-Path -Path $modsInstallDir -ChildPath $modId

  # Determine actual source directory based on branch
  $modSrcDir = Join-Path -Path $modSrcToplevelDir.FullName -ChildPath "WindowsNoEditor"
  $modInfoFile = Join-Path -Path $modSrcDir -ChildPath "mod.info"
  $modMetaFile = Join-Path -Path $modSrcDir -ChildPath "modmeta.info"

  if (-not (Test-Path -LiteralPath $modSrcDir -PathType Container)) {
    $modInfoFileToplevel = Join-Path -Path $modSrcToplevelDir.FullName -ChildPath "mod.info"
    if (Test-Path -LiteralPath $modInfoFileToplevel -PathType Leaf) {
      $modSrcDir = $modSrcToplevelDir.FullName
      $modInfoFile = $modInfoFileToplevel
      $modMetaFile = Join-Path -Path $modSrcDir -ChildPath "modmeta.info"
    } else {
      Write-Host "  Error: Mod source directory for branch Windows in '$($modSrcToplevelDir.FullName)'. Cannot find mod.info. Skipping mod $modId."
      return
  } elseif (-not (Test-Path -LiteralPath $modInfoFile -PathType Leaf)) {
    Write-Host "  Error: Found branch directory $modSrcDir, but it's missing mod.info. Skipping mod $modId."
    return
  }

  # --- Sync/Copy Files ---
  try {
    if (Test-Path -LiteralPath $modDestDir) {
      Remove-Item -LiteralPath $modDestDir -Recurse -Force -ErrorAction Stop
    }
    Copy-Item -LiteralPath $modSrcDir -Destination $modsInstallDir -Recurse -Force -ErrorAction Stop
  } catch {
    Write-Host "  Error copying files for mod $modId from $modSrcDir to $modsInstallDir. Error: $($_.Exception.Message). Skipping mod $modId."
    return
  }

  # --- Decompress .z files (using Perl) ---
  $zFiles = Get-ChildItem -Path $modDestDir -Recurse -Filter *.z -ErrorAction SilentlyContinue
  if ($zFiles) {
    $perlDecompressScript = 'use strict; use warnings; use File::Basename; use File::Copy; use Compress::Raw::Zlib; my ($infile, $outfile) = @ARGV; my $tempoutfile = $outfile . ".tmpperl$$"; open(IN, "<:raw", $infile) or die "Cannot open input $infile: $!"; my $sig; read(IN, $sig, 8) == 8 or die "Unable to read signature from $infile: $!"; if ($sig ne "\xC1\x83\x2A\x9E\x00\x00\x00\x00") { die "Bad file magic in $infile"; } my $header; read(IN, $header, 24) == 24 or die "Unable to read header from $infile: $!"; my ($cl, $ch, $ctl, $cth, $utl, $uth) = unpack("(L<L<L<L<L<L<)", $header); my @chunks = (); my $cu = 0; while ($cu < $ctl) { my $chdr; read(IN, $chdr, 16) == 16 or die "Unable to read chunk header from $infile: $!"; my ($csl, $csh, $usl, $ush) = unpack("(L<L<L<L<)", $chdr); push @chunks, $csl; $cu += $csl; } open(OUT, ">:raw", $tempoutfile) or die "Cannot open output $tempoutfile: $!"; foreach my $cs (@chunks) { my $d; read(IN, $d, $cs) == $cs or die "File read failed for chunk in $infile: $!"; my ($inf, $st) = new Compress::Raw::Zlib::Inflate(); my $o; $st = $inf->inflate($d, $o, 1); if ($st != Z_OK && $st != Z_STREAM_END) { die "Decompression error in $infile; status: $st"; } print OUT $o; } close IN; close OUT; unless (rename($tempoutfile, $outfile)) { unlink $tempoutfile; die "Failed to rename $tempoutfile to $outfile: $!"; } exit 0;'

    foreach ($zFileItem in $zFiles) {
      $zSrcFile = $zFileItem.FullName
      $zDestFile = $zSrcFile -replace '\.z$'
      if (-not (Test-Path -LiteralPath $zDestFile) -or ($zFileItem.LastWriteTimeUtc -gt (Get-Item -LiteralPath $zDestFile -ErrorAction SilentlyContinue).LastWriteTimeUtc)) {
        # Execute Perl simply, check exit code, suppress stderr from PS side
        & $perlPath.Path -e $perlDecompressScript $zSrcFile $zDestFile 2>$null
        if ($?) { # Check if last command succeeded
          (Get-Item -LiteralPath $zDestFile).LastWriteTimeUtc = $zFileItem.LastWriteTimeUtc
          Remove-Item -LiteralPath $zSrcFile -Force -ErrorAction SilentlyContinue
        } else {
          # Silently remove partial file on failure
          if (Test-Path -LiteralPath $zDestFile) { Remove-Item -LiteralPath $zDestFile -Force -ErrorAction SilentlyContinue }
        }
      } else {
        # Remove copied .z file if target exists and is newer/same
        Remove-Item -LiteralPath $zSrcFile -Force -ErrorAction SilentlyContinue
      }
    }
  }

  # --- Generate .mod File ---
  $modOutputFile = Join-Path -Path $modsInstallDir -ChildPath "$($modId).mod"

  if (-not (Test-Path -LiteralPath $modInfoFile -PathType Leaf)) {
    Write-Host "  Error: $modInfoFile not found! Cannot generate .mod file. Skipping mod $modId."
    return
  }

  # Fetch mod name from Steam Community
  $modName = ""
  try {
    $response = Invoke-WebRequest -Uri "http://steamcommunity.com/sharedfiles/filedetails/?id=${modId}" -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
    if ($response -ne $null -and $response.StatusCode -eq 200) {
      if ($response.Content -match '<div class="workshopItemTitle">([^<]*)</div>') {
        $modName = $Matches[1].Trim()
      }
    }
  } catch {
    # Silently ignore exceptions
  }

  # Use Perl to read mod.info and write .mod file
  $perlModGenScript = @'
use strict; use warnings; use File::Basename;
# Args: arkserverdir_rel (ARGV[0]), modId_str (ARGV[1]), modName_fetched (ARGV[2])
# Input: mod.info on STDIN
# Output: .mod file core structure on STDOUT
my ($arkserverdir_rel, $modId_str, $modName_fetched) = @ARGV;
my $data; { local $/; $data = <STDIN>; }
my $mapnamelen = unpack("L<", substr($data, 0, 4));
my $mapname = $mapnamelen > 0 ? substr($data, 4, $mapnamelen - 1) : "";
my $nummaps_offset = 4 + $mapnamelen; my $nummaps = unpack("L<", substr($data, $nummaps_offset, 4));
my $pos = $nummaps_offset + 4;
my $modname = ($modName_fetched || $mapname);
$modname .= "\x00"; my $modnamelen = length($modname);
my $modpath = "../../../" . $arkserverdir_rel . "/Content/Mods/" . $modId_str . "\x00"; my $modpathlen = length($modpath);
my $modid_packed = pack("L<", int($modId_str));
binmode STDOUT;
print $modid_packed; print pack("L<", 0); print pack("L<", $modnamelen); print $modname; print pack("L<", $modpathlen); print $modpath; print pack("L<", $nummaps);
my $map_read_pos = $pos;
for (my $mapnum = 0; $mapnum < $nummaps; $mapnum++){
    my $mapfilelen = unpack("@" . ($map_read_pos) . " L<", $data);
    my $mapfile = $mapfilelen > 0 ? substr($data, $map_read_pos + 4, $mapfilelen) : "";
    my $mapfilepackedlen = $mapfilelen;
    print pack("L<", $mapfilepackedlen); print $mapfile;
    $map_read_pos += (4 + $mapfilelen);
}
print "\x33\xFF\x22\xFF\x02\x00\x00\x00\x01";
exit 0;
'@

  # Execute the Perl script using STDIN/STDOUT redirection, check exit code
  try {
    Get-Content -LiteralPath $modInfoFile -Encoding Byte -Raw |
      & $perlPath.Path -e $perlModGenScript "ShooterGame" $modId "$modName" 2>$null |
      Set-Content -Path $modOutputFile -Encoding Byte -NoNewline -ErrorAction Stop

    # Append modmeta.info if it exists, otherwise append default footer
    if (Test-Path -LiteralPath $modMetaFile -PathType Leaf) {
      # Silently attempt append
      Add-Content -Path $modOutputFile -Value (Get-Content -LiteralPath $modMetaFile -Encoding Byte -Raw) -ErrorAction SilentlyContinue
    } else {
      # Default ModType footer (Type 1), append directly as binary
      $fallbackBytes = [byte[]](0x01,0x00,0x00,0x00, 0x08,0x00,0x00,0x00, 0x4D,0x6F,0x64,0x54,0x79,0x70,0x65,0x00, 0x02,0x00,0x00,0x00, 0x31,0x00)
      # Silently attempt append
      Add-Content -Path $modOutputFile -Value $fallbackBytes -ErrorAction SilentlyContinue
    }
    # Set timestamp of .mod file to match the mod.info file
    try {
      (Get-Item -LiteralPath $modOutputFile).LastWriteTimeUtc = (Get-Item -LiteralPath $modInfoFile).LastWriteTimeUtc
    } catch { } # Silently ignore timestamp errors

  } catch {
    # Handle failure of Perl script to generate .mod file
    Write-Host "  Error: Failed to generate .mod file for $modId using Perl. Skipping."
    if (Test-Path -LiteralPath $modOutputFile) { Remove-Item -LiteralPath $modOutputFile -Force -ErrorAction SilentlyContinue } # Clean up potentially empty/partial file
    return
  }

}
Write-Host "Mod installation process finished."
exit 0