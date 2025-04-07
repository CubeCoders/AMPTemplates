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
if (-not (Get-Command perl -ErrorAction SilentlyContinue)) {
  Write-Host "Error: Executable 'perl' is not found. Please install it, ideally from https://strawberryperl.com, and add it to the System PATH."
  exit 1
}

if (-not (perl -MCompress::Raw::Zlib -e '1' 2>&1)) {
  Write-Host "Error: Perl module 'Compress::Raw::Zlib' not found. Please install it."
  exit 1
}

# --- Variables ---
$workshopContentDir = ".\376030\steamapps\workshop\content\346110"
$modsInstallDir = ".\376030\ShooterGame\Content\Mods"
$modIds = @()

# Function to install a mod with retry on timeout
function Download-Mod {
  param (
    [string]$modId
  )
  
  $retry = 0
  $maxRetries = 5

  while ($true) {
    $output = & .\steamcmd.exe +force_install_dir 376030 +login anonymous +workshop_download_item 346110 $modId validate +quit 2>&1
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
  $modOutputFile = ""
  $modInfoFile = ""
  $modmetaFile = ""
  $modName = ""
  $srcFile = ""
  $destFile = ""

  New-Item -ItemType Directory -Force -Path $modDestDir

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
  Get-ChildItem -Path $modSrcDir -Directory -Recurse | ForEach-Object {
    $destDir = "$modDestDir\$($_.FullName.Substring($modSrcDir.Length))"
    New-Item -ItemType Directory -Force -Path $destDir
  }

  # Remove files in destination not present in source
  Get-ChildItem -Path $modDestDir -File | ForEach-Object {
    $file = $_.FullName.Substring($modDestDir.Length + 1)
    if (-not (Test-Path "$modSrcDir\$file") -and -not (Test-Path "$modSrcDir\$file.z")) {
      Remove-Item "$modDestDir\$file"
    }
  }

  # Remove empty directories in destination
  Get-ChildItem -Path $modDestDir -Directory -Recurse | ForEach-Object {
    $dir = $_.FullName.Substring($modDestDir.Length + 1)
    if (-not (Test-Path "$modSrcDir\$dir")) {
      Remove-Item $_.FullName -Recurse
    }
  }

  # Hardlink regular files
  Get-ChildItem -Path $modSrcDir -File | ForEach-Object {
    $srcFile = $_.FullName
    $destFile = Join-Path $modDestDir $_.Name
    if (-not (Test-Path $destFile) -or (Get-Item $srcFile).LastWriteTime -gt (Get-Item $destFile).LastWriteTime) {
      Create-HardLink -sourceFile $srcFile -destinationFile $destFile
    }
  }

  # Decompress .z files
  Get-ChildItem -Path $modSrcDir -File -Filter "*.z" | ForEach-Object {
    $srcFile = $_.FullName
    $destFile = "$modDestDir\$($_.Name.Substring(0, $_.Name.Length - 2))"
    if (-not (Test-Path $destFile) -or (Get-Item $srcFile).LastWriteTime -gt (Get-Item $destFile).LastWriteTime) {
      # Uncompress .z files with Perl
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
      ' < $srcFile > $destFile
      # Touch the file to preserve timestamp
      (Get-Item $srcFile).CreationTimeUtc | Set-ItemProperty -Path $destFile -Name CreationTimeUtc
    }
  }

  # --- Generate .mod File ---
  $modOutputFile = "$modsInstallDir\$modId.mod"
  $modInfoFile = "$modSrcDir\mod.info"
  if (-not (Test-Path $modInfoFile)) {
    Write-Host "  Error: $modInfoFile not found! Cannot generate .mod file. Skipping mod $modId."
    return
  }

  # Fetch mod name from Steam Community
  $modName = Invoke-RestMethod "http://steamcommunity.com/sharedfiles/filedetails/?id=$modId" | Select-String -Pattern '<div class="workshopItemTitle">([^<]*)</div>' | ForEach-Object { $_.Matches.Groups[1].Value } | Select-Object -First 1

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
  ' "ShooterGame" "$modId" "$modName" < $modInfoFile > $modOutputFile

  # Append modmeta.info if it exists, otherwise append default footer
  $modmetaFile = "$modSrcDir\modmeta.info"
  if (Test-Path $modmetaFile) {
    Get-Content $modmetaFile | Add-Content $modOutputFile
  } else {
    [System.IO.File]::AppendAllText($modOutputFile, '\x01\x00\x00\x00\x08\x00\x00\x00ModType\x00\x02\x00\x00\x001\x00')
  }

  # Set timestamp of .mod file to match the mod.info file
  (Get-Item $modInfoFile).CreationTimeUtc | Set-ItemProperty -Path $modOutputFile -Name CreationTimeUtc
}

# --- Main Loop ---
if ($args.Length -eq 0) {
  Write-Host "No mod IDs specified"
  exit 1
}

Write-Host "Installing/updating mods..."

$modIds = $args[0] -replace '^"(.*)"$', '$1'
$modIds = $modIds.Split(',')

foreach ($modId in $modIds) {
  Download-Mod -modId $modId
  Install-Mod -modId $modId
}

Write-Host "Mod installation/update process finished."
exit 0
