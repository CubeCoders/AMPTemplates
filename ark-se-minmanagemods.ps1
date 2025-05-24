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

# --- Variables ---
$arkRootDir = Join-Path $PSScriptRoot "arkse"
$arkBaseDir = Join-Path $arkRootDir "376030"
$workshopContentDir = Join-Path $arkBaseDir "steamapps\workshop\content\346110"
$modsInstallDir = Join-Path $arkBaseDir "ShooterGame\Content\Mods"

# Function to set up the environment for Strawberry Perl
function Setup-StrawberryPerl {

  $perlRoot = Join-Path $PSScriptRoot "arkse\perl"
  $perlBin  = Join-Path $PerlRoot "perl\bin"
  $perlCbin = Join-Path $PerlRoot "c\bin"
  $perlExe  = Join-Path $perlBin "perl.exe"

  # Check if Perl is already installed
  if (-not (Test-Path $perlExe)) {
    $zipUrl = "https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54001_64bit_UCRT/strawberry-perl-5.40.0.1-64bit-portable.zip"
    $zipFile = "$env:TEMP\strawberry-perl.zip"

    try {
      if (-not (Test-Path $zipFile)) {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing
      }

      if (-not (Test-Path $perlRoot)) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $perlRoot)
      }
    } catch {
      Write-Host "  Error: Failed to download or extract Strawberry Perl. Aborting."
      return $false
    }

    if (-not (Test-Path $perlExe)) {
      Write-Host "  Error: Failed to extract Strawberry Perl. Aborting."
      return $false
    }
  }
  
  # Add Strawberry Perl to PATH
  $env:PATH = "$perlBin;$perlCbin;$env:PATH"

  # Install cpanm if it's not available
  if (-not (Get-Command cpanm -ErrorAction SilentlyContinue)) {
    try {
      & perl -MCPAN -e "install App::cpanminus"
    } catch {
      Write-Host "  Error: Failed to install cpanminus. Aborting."
      return $false
    }
  }

  $requiredPerlModules = @(
    'Compress::Raw::Zlib',
    'Win32::LongPath'
  )

  try {
    & cpanm --notest --quiet @requiredPerlModules
  } catch {
    Write-Host "  Error: Failed to install required Perl modules $requiredPerlModules. Aborting."
    return $false
  }

  return $true
}

# Function to install a mod with retry on timeout
function Download-Mod {
  param([string]$modId)

  $steamExe = Join-Path $arkRootDir "steamcmd.exe"
  $steamInstallDir = $arkBaseDir
  $maxRetries = 5
  for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    Write-Host "Downloading mod $modId"
    $output = & "$steamExe" +force_install_dir "$steamInstallDir" +login anonymous +workshop_download_item 346110 $modId validate +quit 2>&1

    if ($output -match "Success\. Downloaded item $modId") {
      Write-Host "Mod $modId downloaded successfully"
      return $true
    }

    Write-Host "  Error: Download failed for mod $modId. Retrying..."
    Start-Sleep -Seconds 2
  }

  Write-Host "  Error: Mod $modId download failed after $maxRetries attempts"
  return $false
}

# Function to extract and install downloaded mod files
function Install-Mod {
  param (
    [string]$modId
  )

  Write-Host "Extracting and installing mod $modId"
  $modDestDir = Join-Path $modsInstallDir $modId
  $modSrcToplevelDir = Join-Path $workshopContentDir $modId
  $modSrcDir = $null
  $modOutputFile = $null
  $modInfoFile = $null
  $modmetaFile = $null
  $modName = $null
  $srcFile = $null
  $destFile = $null

  if (-not (Test-Path $modDestDir)) {
    New-Item -ItemType Directory -Path $modDestDir -Force > $null
  }

  # Determine actual source directory based on branch
  $modSrcDir = Join-Path $modSrcToplevelDir "WindowsNoEditor"

  if (-not (Test-Path $modSrcDir)) {
    $modInfoCheckPath = Join-Path $modSrcToplevelDir "mod.info"
    if (Test-Path $modInfoCheckPath) {
      $modSrcDir = $modSrcToplevelDir
    } else {
      Write-Host "  Error: Mod source directory not found for branch Windows in $modSrcToplevelDir. Cannot find mod.info. Skipping mod $modId."
      return
    }
  } elseif (-not (Test-Path (Join-Path $modSrcDir "mod.info"))) {
    Write-Host "  Error: Found branch directory $modSrcDir, but it's missing mod.info. Skipping mod $modId."
    return
  }

  # Helper function to get relative path
  function Get-RelativePath {
    param(
      [string]$ReferencePath,
      [string]$ItemPath
    )
    if (-not $ReferencePath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
      $ReferencePath += [System.IO.Path]::DirectorySeparatorChar
    }
    $baseUri = [System.Uri]::new($ReferencePath)
    $itemUri = [System.Uri]::new($ItemPath)
    $relativeUri = $baseUri.MakeRelativeUri($itemUri)
    $relPath = [System.Uri]::UnescapeDataString($relativeUri.OriginalString)
    return $relPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
  }

  # Create necessary sub-directories in destination
  Get-ChildItem -Path $modSrcDir -Directory -Recurse | ForEach-Object {
    $relativePath = Get-RelativePath -ReferencePath $modSrcDir -ItemPath $_.FullName
    $destPath = Join-Path $modDestDir $relativePath
    if (-not (Test-Path $destPath)) {
      New-Item -ItemType Directory -Path $destPath -Force > $null
    }
  }

  # Remove files in destination not present in source
  Get-ChildItem -Path $modDestDir -File -Recurse | Where-Object { $_.Name -notmatch '^\.' } | ForEach-Object {
    $relativePath = Get-RelativePath -ReferencePath $modDestDir -ItemPath $_.FullName
    $srcPath = Join-Path $modSrcDir $relativePath
    $srcZPath = "$srcPath.z"

    if (-not (Test-Path $srcPath) -and -not (Test-Path $srcZPath)) {
      Remove-Item -Force -Path $_.FullName
    }
  }

  # Remove empty directories in destination
  Get-ChildItem -Path $modDestDir -Directory -Recurse | Sort-Object FullName -Descending | ForEach-Object {
    $relativePath = Get-RelativePath -ReferencePath $modDestDir -ItemPath $_.FullName
    $srcDir = Join-Path $modSrcDir $relativePath
    if (-not (Test-Path -Path $srcDir -PathType Container)) {
      try {
        Remove-Item -Path $_.FullName -Force -ErrorAction Stop
      } catch { }
    }
  }

  # Copy or hardlink regular files
  Get-ChildItem -Path $modSrcDir -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Extension -ne '.z' -and $_.Name -notlike '*.z.uncompressed_size' } |
  ForEach-Object {
    $srcFile = $_.FullName
    $relativePath = Get-RelativePath -ReferencePath $modSrcDir -ItemPath $srcFile
    $destFile = Join-Path $modDestDir $relativePath

    $destDir = Split-Path $destFile
    if (-not (Test-Path $destDir)) {
      New-Item -ItemType Directory -Path $destDir -Force > $null
    }

    if (-not (Test-Path $destFile) -or
      ([System.IO.File]::GetLastWriteTimeUtc($srcFile) -gt [System.IO.File]::GetLastWriteTimeUtc($destFile))) {
      try {
        if (Test-Path $destFile) {
          Remove-Item $destFile -Force > $null
        }
        New-Item -ItemType HardLink -Path $destFile -Target $srcFile -ErrorAction Stop > $null
      } catch {
        Copy-Item -Path $srcFile -Destination $destFile -Force -ErrorAction SilentlyContinue > $null
      }
    }
  }

  $decompressScript = @'
use Compress::Raw::Zlib;
use Win32::LongPath qw(openL);

my ($infile, $outfile) = @ARGV;

my ($in, $out);
openL(\$in, '<:raw', $infile);
openL(\$out, '>:raw', $outfile);

my $sig;
read($in, $sig, 8) or die "Unable to read compressed file: $!";
if ($sig != "\xC1\x83\x2A\x9E\x00\x00\x00\x00"){
  die "Bad file magic";
}

my $data;
read($in, $data, 24) or die "Unable to read compressed file: $!";
my ($chunksizelo, $chunksizehi,
    $comprtotlo,  $comprtothi,
    $uncomtotlo,  $uncomtothi) = unpack("(LLLLLL)<", $data);

my @chunks = ();
my $comprused = 0;
while ($comprused < $comprtotlo) {
  read($in, $data, 16) or die "Unable to read read compressed file: $!";
  my ($comprsizelo, $comprsizehi,
      $uncomsizelo, $uncomsizehi) = unpack("(LLLL)<", $data);
  push @chunks, $comprsizelo;
  $comprused += $comprsizelo;
}

foreach my $comprsize (@chunks) {
  read($in, $data, $comprsize) == $comprsize or die "File read failed: $!";
  my ($inflate, $status) = new Compress::Raw::Zlib::Inflate();
  my $output;
  $status = $inflate->inflate($data, $output, 1);
  if ($status != Z_STREAM_END) {
    die "Bad compressed stream; status: " . ($status);
  }
  if (length($data) != 0) {
    die "Unconsumed data in input"
  }
  print $out $output;
}

close($out);
close($in);
exit 0;
'@

  $decompressScriptFile = Join-Path $env:TEMP "decompress.pl"
  Set-Content -Path $decompressScriptFile -Value $decompressScript -Encoding ASCII -Force

  Get-ChildItem -Path $modSrcDir -Recurse -Filter '*.z' -File | ForEach-Object {
    $srcFile = $_.FullName
    $relativePath = Get-RelativePath -ReferencePath $modSrcDir -ItemPath $srcFile
    $destFile = Join-Path $modDestDir ($relativePath -replace '\.z$', '')

    if (-not (Test-Path $destFile) -or
      ([System.IO.File]::GetLastWriteTimeUtc($srcFile) -gt [System.IO.File]::GetLastWriteTimeUtc($destFile))) {

      $destDir = Split-Path $destFile
      if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force > $null
      }

      try {
        & perl $decompressScriptFile "$srcFile" "$destFile"
        # Update timestamp to match source
        $ts = [System.IO.File]::GetLastWriteTimeUtc($srcFile)
        [System.IO.File]::SetLastWriteTimeUtc($destFile, $ts)
      } catch {
        Write-Host "  Error: Decompression failed for mod $modId. Skipping."
        return
      }
    }
  }
  
  $modOutputFile = Join-Path $modsInstallDir "$modId.mod"
  $modInfoFile = Join-Path $modSrcDir "mod.info"

  if (-not (Test-Path -LiteralPath $modInfoFile)) {
    Write-Host "  Error: $modInfoFile not found! Cannot generate .mod file. Skipping mod $modId."
    return
  }

  # Fetch mod name from Steam Community
  try {
    $modName = Invoke-WebRequest -UseBasicParsing -Uri "http://steamcommunity.com/sharedfiles/filedetails/?id=$modId" |
      Select-String -Pattern '<div class="workshopItemTitle">([^<]*)</div>' |
      ForEach-Object { $_.Matches[0].Groups[1].Value }
  } catch {
    $modName = ""
  }

  $createModfileScript = @'
use Win32::LongPath qw(openL);

my $infile = @ARGV[0];
my $outfile = @ARGV[1];
my ($in, $out);

openL(\$in, "<:raw", $infile);
openL(\$out, ">:raw", $outfile);

my $data;
{ local $/; $data = <$in>; }
my $mapnamelen = unpack("@0 L<", $data);
  my $mapname = substr($data, 4, $mapnamelen - 1);
  my $nummaps = unpack("@" . ($mapnamelen + 4) . " L<", $data);
  my $pos = $mapnamelen + 8;
  my $modname = ($ARGV[4] || $mapname) . "\x00";
  my $modnamelen = length($modname);
  my $modpath = "../../../" . $ARGV[2] . "/Content/Mods/" . $ARGV[3] . "\x00";
  my $modpathlen = length($modpath);
  print $out pack("L< L< L< Z$modnamelen L< Z$modpathlen L<",
    $ARGV[3], 0, $modnamelen, $modname, $modpathlen, $modpath,
    $nummaps);
  for (my $mapnum = 0; $mapnum < $nummaps; $mapnum++){
    my $mapfilelen = unpack("@" . ($pos) . " L<", $data);
    my $mapfile = substr($data, $mapnamelen + 12, $mapfilelen);
    print $out pack("L< Z$mapfilelen", $mapfilelen, $mapfile);
    $pos = $pos + 4 + $mapfilelen;
  }
print $out "\x33\xFF\x22\xFF\x02\x00\x00\x00\x01";
close($out);
close($in);
'@

  $createModfileScriptFile = Join-Path $env:TEMP "createModfile.pl"
  Set-Content -Path $createModfileScriptFile -Value $createModfileScript -Encoding ASCII -Force

  try {
    & perl $createModfileScriptFile "$modInfoFile" "$modOutputFile" "ShooterGame" "$modId" "$modName"
  } catch {
    Write-Host "  Error: Failed to create .mod file for mod $modId. Skipping."
    return
  }

  $modmetaFile = Join-Path $modSrcDir "modmeta.info"
  if (Test-Path $modmetaFile) {
    Get-Content -Encoding Byte $modmetaFile | Add-Content -Encoding Byte $modOutputFile
  } else {
    $footer = [byte[]](0x01,0x00,0x00,0x00,0x08,0x00,0x00,0x00) +
              [System.Text.Encoding]::ASCII.GetBytes("ModType") +
              0x00,0x02,0x00,0x00,0x00 +
              [System.Text.Encoding]::ASCII.GetBytes("1") +
              0x00
    [System.IO.File]::WriteAllBytes($modOutputFile, ([System.IO.File]::ReadAllBytes($modOutputFile) + $footer))
  }

  # Match timestamp to mod.info
  $ts = [System.IO.File]::GetLastWriteTimeUtc($modInfoFile)
  [System.IO.File]::SetLastWriteTimeUtc($modOutputFile, $ts)

  Write-Host "Mod $modId extracted and installed successfully"
}

# --- Main Loop ---
if ($args.Length -eq 0) {
  Write-Host "No mod IDs specified"
  exit 1
}

Write-Host "Installing/updating mods..."

$modIds = $args[0] -replace '^"(.*)"$', '$1'
$modIds = $modIds.Split(',')

if (Setup-StrawberryPerl) {
  foreach ($modId in $modIds) {
    if (Download-Mod -modId $modId) {
      Install-Mod -modId $modId
    }
  }
}

Write-Host "Mod installation/update process finished."
exit 0
