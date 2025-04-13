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
      $perlScript = @'
binmode(STDIN);
binmode(STDOUT);
my $sig;
read(STDIN, $sig, 8) or die "Unable to read compressed file: $!";
if ($sig != "\xC1\x83\x2A\x9E\x00\x00\x00\x00") {
  die "Bad file magic";
}
my $data;
read(STDIN, $data, 24) or die "Unable to read compressed file: $!";
my ($chunksizelo, $chunksizehi,
  $comprtotlo,  $comprtothi,
  $uncomtotlo,  $uncomtothi)  = unpack('V6', $data);
my @chunks = ();
my $comprused = 0;
while ($comprused < $comprtotlo) {
  read(STDIN, $data, 16) or die "Unable to read compressed file: $!";
  my ($comprsizelo, $comprsizehi,
    $uncomsizelo, $uncomsizehi) = unpack('V4', $data);
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
'@

      # Save Perl script to temp file
      $perlTemp = "$env:TEMP\decompress_temp.pl"
      Set-Content -Path $perlTemp -Value $perlScript -Encoding ASCII

      # Use cmd.exe to run it with binary redirection
      Start-Process -FilePath "cmd.exe" -ArgumentList "/c perl -MCompress::Raw::Zlib `"$perlTemp`" < `"$srcFile`" > `"$destFile`"" -Wait -NoNewWindow

      # Preserve timestamp
      $srcTime = (Get-Item $srcFile).LastWriteTimeUtc
      (Get-Item $destFile).LastWriteTimeUtc = $srcTime
    }
  }

  
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
