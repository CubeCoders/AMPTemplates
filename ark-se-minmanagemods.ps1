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

# Function to set up the environment for Strawberry Perl
function Setup-StrawberryPerl {

  $perlRoot = Join-Path $PSScriptRoot "arkse\perl"
  $perlBin  = Join-Path $PerlRoot "perl\bin"
  $perlCbin = Join-Path $PerlRoot "c\bin"

  # Add Strawberry Perl to PATH
  $env:PATH = "$perlBin;$perlCbin;$env:PATH"

  # Check if the module is already installed
  & perl -e "eval { require Compress::Raw::Zlib } or exit 1"
  if ($LASTEXITCODE -eq 0) {
      return
  }

  # Install cpanm if it's not available
  if (-not (Get-Command cpanm -ErrorAction SilentlyContinue)) {
      & perl -MCPAN -e "install App::cpanminus"
  }

  # Install the module silently
  & cpanm --notest --quiet Compress::Raw::Zlib
}

# Function to install a mod with retry on timeout
function Download-Mod {
  param (
    [string]$modId
  )
  
  $retry = 0
  $maxRetries = 5

  while ($true) {
    $output = & .\steamcmd.exe +force_install_dir 376030 +login anonymous +workshop_download_item 346110 $modId validate +quit 2>&1
    Write-Host $output
    $lastLine = $output | Select-Object -Last 1

    if ($lastLine -match "Timeout downloading item") {
      if ($retry -lt $maxRetries) {
        Write-Host "  Timeout detected. Retrying mod $modId..."
        $retry++
        Start-Sleep -Seconds 2
      } else {
        Write-Host "  Failed after retry: $modId"
        break
      }
    } else {
      Write-Host $lastLine
      break
    }
  }
}

# Function to extract and install downloaded mod files
function Install-Mod {
  param (
    [string]$modId
  )
  
  $modDestDir = "$modsInstallDir\$modId"
  $modSrcToplevelDir = "$workshopContentDir\$modId"
  $modSrcDir = ""
  $modInfoFile = ""
  $modOutputFile = ""
  $modmetaFile = ""
  $modName = ""
  $srcFile = ""
  $destFile = ""

  New-Item -ItemType Directory -Force -Path $modDestDir > $null

  # Determine actual source directory based on branch
  $modSrcDir = "$modSrcToplevelDir\WindowsNoEditor"
  if (-not (Test-Path $modSrcDir)) {
    if (Test-Path "$modSrcToplevelDir\mod.info") {
      $modSrcDir = $modSrcToplevelDir
    } else {
      Write-Host "  Error: Mod source directory not found for branch Windows in $modSrcToplevelDir. Cannot find mod.info. Skipping mod $modId."
      return
    }
  } elseif (-not (Test-Path "$modSrcDir\mod.info")) {
    Write-Host "  Error: Found branch directory $modSrcDir, but it's missing mod.info. Skipping mod $modId."
    return
  }

  # Create necessary sub-directories in destination
  Get-ChildItem -Path $modSrcDir -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $destDir = "$modDestDir\$($_.FullName.Substring($modSrcDir.Length))"
    New-Item -ItemType Directory -Force -Path $destDir > $null
  }

  # Remove files in destination not present in source
  Get-ChildItem -Path $modDestDir -File -ErrorAction SilentlyContinue | ForEach-Object {
    $file = $_.FullName.Substring($modDestDir.Length + 1)
    if (-not (Test-Path "$modSrcDir\$file") -and -not (Test-Path "$modSrcDir\$file.z")) {
      Remove-Item "$modDestDir\$file" -ErrorAction SilentlyContinue > $null
    }
  }

  # Remove empty directories in destination
  Get-ChildItem -Path $modDestDir -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $dir = $_.FullName.Substring($modDestDir.Length + 1)
    if (-not (Test-Path "$modSrcDir\$dir")) {
      Remove-Item $_.FullName -Recurse > $null
    }
  }

  # Hardlink regular files (excluding .z and .z.uncompressed_size)
  Get-ChildItem -Path $modSrcDir -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notlike '*.z' -and $_.Name -notlike '*.z.uncompressed_size'
  } | ForEach-Object {
    $srcFile = $_.FullName
    $destFile = Join-Path $modDestDir $_.Name
    if (-not (Test-Path $destFile) -or (Get-Item $srcFile).LastWriteTime -gt (Get-Item $destFile).LastWriteTime) {
      New-Item -ItemType HardLink -Path $destFile -Target $srcFile > $null
    }
  }

  # Decompress the .z files using Perl
  $decompressScript = @'
use strict;
use warnings;
use Compress::Raw::Zlib;

my ($infile, $outfile) = @ARGV;
open my $in,  '<:raw', $infile  or die "Cannot open $infile: $!";
open my $out, '>:raw', $outfile or die "Cannot open $outfile: $!";

my $sig;
read($in, $sig, 8) or die "Unable to read compressed file: $!";
if ($sig ne "\xC1\x83\x2A\x9E\x00\x00\x00\x00") {
  die "Bad file magic";
}

my $data;
read($in, $data, 24) or die "Unable to read compressed file: $!";
my ($chunksizelo, $chunksizehi,
    $comprtotlo,  $comprtothi,
    $uncomtotlo,  $uncomtothi) = unpack("(LLLLLL)<", $data);

my @chunks;
my $comprused = 0;
while ($comprused < $comprtotlo) {
  read($in, $data, 16) or die "Unable to read compressed file: $!";
  my ($comprsizelo, $comprsizehi,
      $uncomsizelo, $uncomsizehi) = unpack("(LLLL)<", $data);
  push @chunks, $comprsizelo;
  $comprused += $comprsizelo;
}

my $inflate = Compress::Raw::Zlib::Inflate->new();
foreach my $comprsize (@chunks) {
  read($in, $data, $comprsize) or die "File read failed: $!";
  my $output;
  my $status = $inflate->inflate($data, $output, 1);
  
  if ($status != Z_STREAM_END) {
    die "Bad compressed stream; status: $status";
  }
  
  print $out $output;
}

close $out;
close $in;
exit 0;
'@

  $decompressScriptFile = "$env:TEMP\decompress.pl"
  Set-Content -Path $decompressScriptFile -Value $decompressScript -Encoding ASCII

  Get-ChildItem -Path $modSrcDir -Filter *.z -Recurse -File | ForEach-Object {
    $srcFile = $_.FullName
    $relPath = $srcFile.Substring($modSrcDir.Length).TrimStart('\')
    $destFile = Join-Path $modDestDir ($relPath -replace '\.z$', '')

    $destDir = Split-Path $destFile
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    if (-not (Test-Path $destFile) -or ((Get-Item $srcFile).LastWriteTime -gt (Get-Item $destFile).LastWriteTime)) {
      
      # Run the Perl decompression logic
      perl $decompressScriptFile "$srcFile" "$destFile"

      # Preserve timestamp
      $srcTime = (Get-Item $srcFile).LastWriteTimeUtc
      (Get-Item $destFile).LastWriteTimeUtc = $srcTime
    }
  }

  # Generate .mod file
  $modOutputFile = Join-Path $modsInstallDir "$modId.mod"
  $modInfoFile = Join-Path $modSrcDir "mod.info"
  $modmetaFile = Join-Path $modSrcDir "modmeta.info"

  if (!(Test-Path $modInfoFile)) {
      Write-Host "  Error: $modInfoFile not found! Cannot generate .mod file. Skipping mod $modId."
      return
  }

  # Fetch mod name
  $html = Invoke-WebRequest -Uri "http://steamcommunity.com/sharedfiles/filedetails/?id=$modId" -UseBasicParsing
  $modName = ($html.Content -split '<div class="workshopItemTitle">')[1] -split '</div>' | Select-Object -First 1
  $modName = $modName.Trim()

  $createModfileScript = @'
use strict;
use warnings;

my ($game, $modId, $modName, $inputFile, $outputFile, $modmetaFile) = @ARGV;

open my $in,  '<:raw', $inputFile  or die "Cannot open $inputFile: $!";
binmode $in;
my $data;
{ local $/; $data = <$in>; }
close $in;

my $mapnamelen = unpack("@0 L<", $data);
my $mapname = substr($data, 4, $mapnamelen - 1);
my $nummaps = unpack("@" . ($mapnamelen + 4) . " L<", $data);
my $pos = $mapnamelen + 8;

my $modname = ($modName || $mapname) . "\x00";
my $modnamelen = length($modname);
my $modpath = "../../../" . $game . "/Content/Mods/" . $modId . "\x00";
my $modpathlen = length($modpath);

my $output;
$output .= pack("L< L< L< Z$modnamelen L< Z$modpathlen L<",
  $modId, 0, $modnamelen, $modname, $modpathlen, $modpath, $nummaps);

for (my $mapnum = 0; $mapnum < $nummaps; $mapnum++) {
  my $mapfilelen = unpack("@" . ($pos) . " L<", $data);
  my $mapfile = substr($data, $mapnamelen + 12, $mapfilelen);
  $output .= pack("L< Z$mapfilelen", $mapfilelen, $mapfile);
  $pos += 4 + $mapfilelen;
}

$output .= "\x33\xFF\x22\xFF\x02\x00\x00\x00\x01";

# Write to a temp file and append modmeta or default footer
open my $out, '>:raw', $outputFile or die "Cannot open $outputFile: $!";
binmode $out;
print $out $output;

if ($modmetaFile && -e $modmetaFile) {
  open my $meta, '<:raw', $modmetaFile or die "Cannot open $modmetaFile: $!";
  binmode $meta;
  my $modmeta;
  { local $/; $modmeta = <$meta>; }
  print $out $modmeta;
  close $meta;
} else {
  print $out pack("C*", 0x01, 0x00, 0x00, 0x00,
                         0x08, 0x00, 0x00, 0x00,
                         0x4D, 0x6F, 0x64, 0x54, 0x79, 0x70, 0x65, 0x00,
                         0x02, 0x00, 0x00, 0x00,
                         0x31, 0x00);
}

close $out;
exit 0;
'@

  $createModfileScriptFile = "$env:TEMP\create_modfile.pl"
  Set-Content -Path $createModfileScriptFile -Value $createModfileScript -Encoding ASCII
  perl $createModfileScriptFile "$modInfoFile" "$modOutputFile" "ShooterGame" "$modId" "$modName"

  # Append modmeta.info or default footer
  $bytes = [System.IO.File]::ReadAllBytes($modOutputFile)
  $outputStream = New-Object System.IO.MemoryStream
  $outputStream.Write($bytes, 0, $bytes.Length)

  if (Test-Path $modmetaFile) {
      $modmetaBytes = [System.IO.File]::ReadAllBytes($modmetaFile)
      $outputStream.Write($modmetaBytes, 0, $modmetaBytes.Length)
  } else {
      $defaultFooter = [byte[]] (0x01, 0x00, 0x00, 0x00,
                                0x08, 0x00, 0x00, 0x00,
                                0x4D, 0x6F, 0x64, 0x54, 0x79, 0x70, 0x65, 0x00,
                                0x02, 0x00, 0x00, 0x00,
                                0x31, 0x00)
      $outputStream.Write($defaultFooter, 0, $defaultFooter.Length)
  }

  [System.IO.File]::WriteAllBytes($modOutputFile, $outputStream.ToArray())

  # Match timestamp from mod.info
  $srcTime = (Get-Item $modInfoFile).LastWriteTimeUtc
  (Get-Item $modOutputFile).LastWriteTimeUtc = $srcTime
}

# --- Main Loop ---
if ($args.Length -eq 0) {
  Write-Host "No mod IDs specified"
  exit 1
}

Write-Host "Installing/updating mods..."

Set-Location -Path '.\arkse'

$workshopContentDir = Resolve-Path ".\376030\steamapps\workshop\content\346110"
$modsInstallDir = Resolve-Path ".\376030\ShooterGame\Content\Mods"
$modIds = $args[0] -replace '^"(.*)"$', '$1'
$modIds = $modIds.Split(',')

Setup-StrawberryPerl

foreach ($modId in $modIds) {
  Download-Mod -modId $modId
  Install-Mod -modId $modId
}

Write-Host "Mod installation/update process finished."
exit 0
