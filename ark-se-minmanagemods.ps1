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

  # Install cpanm if it's not available
  if (-not (Get-Command cpanm -ErrorAction SilentlyContinue)) {
      & perl -MCPAN -e "install App::cpanminus"
  }

  $requiredPerlModules = @(
    'Compress::Raw::Zlib',
    'Win32::LongPath'
  )

  try {
    & cpanm --notest --quiet $requiredPerlModules
  } catch {
      Write-Host "  Error: Failed to install required Perl modules $requiredPerlModules. Aborting."
    exit 1
  }
}

# Function to install a mod with retry on timeout
function Download-Mod {
  param (
    [string]$modId
  )
  
  Set-Location -Path "$PSScriptRoot\arkse"

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

function Install-Mod {
  param (
    [string]$modId
  )

  Set-Location -Path "$PSScriptRoot\arkse\376030"

  $workshopContentDir = "steamapps\workshop\content\346110"
  $modsInstallDir = "ShooterGame\Content\Mods"

  try {
      $AbsoluteWorkshopContentDir = (Resolve-Path -Path $workshopContentDir -ErrorAction Stop).ProviderPath
      $AbsoluteModsInstallDir = (Resolve-Path -Path $modsInstallDir -ErrorAction Stop).ProviderPath
      $AbsoluteArkBase = (Get-Location).ProviderPath
  } catch {
       Write-Host "  Error: Could not resolve base relative paths like '$workshopContentDir'. Ensure CWD is correct."
       return
  }

  $AbsoluteModDestDir = Join-Path $AbsoluteModsInstallDir $modId
  $AbsoluteModSrcToplevelDir = Join-Path $AbsoluteWorkshopContentDir $modId
  $AbsoluteModSrcDir = ""
  $modName = ""

  if (-not (Test-Path $AbsoluteModDestDir)) {
    New-Item -ItemType Directory -Force -Path $AbsoluteModDestDir > $null
  }

  $potentialAbsoluteSrcDir = Join-Path $AbsoluteModSrcToplevelDir "WindowsNoEditor"
  if (-not (Test-Path $potentialAbsoluteSrcDir)) {
    $absoluteModInfoCheckPath = Join-Path $AbsoluteModSrcToplevelDir "mod.info"
    if (Test-Path $absoluteModInfoCheckPath) {
      $AbsoluteModSrcDir = $AbsoluteModSrcToplevelDir
    } else {
      Write-Host "  Error: Mod source directory not found for branch Windows in $AbsoluteModSrcToplevelDir. Cannot find mod.info. Skipping mod $modId."
      return
    }
  } else {
    $AbsoluteModSrcDir = $potentialAbsoluteSrcDir
    $absoluteModInfoCheckPath = Join-Path $AbsoluteModSrcDir "mod.info"
    if (-not (Test-Path $absoluteModInfoCheckPath)) {
      Write-Host "  Error: Found branch directory $AbsoluteModSrcDir, but it's missing mod.info. Skipping mod $modId."
      return
    }
  }

  $ResolvedSourceBase = Resolve-Path -Path $AbsoluteModSrcDir -ErrorAction SilentlyContinue
  $ResolvedDestBase = Resolve-Path -Path $AbsoluteModDestDir -ErrorAction SilentlyContinue
  if (-not $ResolvedSourceBase -or -not $ResolvedDestBase) {
     Write-Host "  Error: Could not resolve final base paths. Skipping mod $modId."
     return
  }
  $AbsoluteModSrcDir = $ResolvedSourceBase.ProviderPath
  $AbsoluteModDestDir = $ResolvedDestBase.ProviderPath

  Function Get-RelativePath {
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

  Get-ChildItem -Path $AbsoluteModSrcDir -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $relativeDirPath = Get-RelativePath -ReferencePath $AbsoluteModSrcDir -ItemPath $_.FullName
    $destDirAbsolute = Join-Path $AbsoluteModDestDir $relativeDirPath
    if (-not (Test-Path $destDirAbsolute)) {
      New-Item -ItemType Directory -Force -Path $destDirAbsolute > $null
    }
  }

  Get-ChildItem -Path $AbsoluteModDestDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $relPath = Get-RelativePath -ReferencePath $AbsoluteModDestDir -ItemPath $_.FullName
    $srcFileAbsolute = Join-Path $AbsoluteModSrcDir $relPath
    $srcZFileAbsolute = "$srcFileAbsolute.z"
    if (-not (Test-Path $srcFileAbsolute) -and -not (Test-Path $srcZFileAbsolute)) {
      Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue > $null
    }
  }

  Get-ChildItem -Path $AbsoluteModDestDir -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $dirRelPath = Get-RelativePath -ReferencePath $AbsoluteModDestDir -ItemPath $_.FullName
    $srcDirPathAbsolute = Join-Path $AbsoluteModSrcDir $dirRelPath
    if (-not (Test-Path $srcDirPathAbsolute)) {
      Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue > $null
    }
  }
  Get-ChildItem -Path $AbsoluteModDestDir -Directory -Recurse -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
      if ((Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue).Count -eq 0) {
         Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue > $null
      }
  }

  Get-ChildItem -Path $AbsoluteModSrcDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notlike '*.z' -and $_.Name -notlike '*.z.uncompressed_size'
  } | ForEach-Object {
    $relPath = Get-RelativePath -ReferencePath $AbsoluteModSrcDir -ItemPath $_.FullName
    $srcFileAbsolute = $_.FullName
    $destFileAbsolute = Join-Path $AbsoluteModDestDir $relPath

    $needsLink = $true
    if (Test-Path $destFileAbsolute) {
       if ((Get-Item $srcFileAbsolute).LastWriteTimeUtc -le (Get-Item $destFileAbsolute).LastWriteTimeUtc) {
           $needsLink = $false
       } else {
           Remove-Item -Path $destFileAbsolute -Force > $null
       }
    }
    if ($needsLink) {
        $parentDirAbsolute = Split-Path -Path $destFileAbsolute -Parent
        if ($parentDirAbsolute -and (-not (Test-Path $parentDirAbsolute))) {
            New-Item -ItemType Directory -Force -Path $parentDirAbsolute > $null
        }
        New-Item -ItemType HardLink -Path $destFileAbsolute -Target $srcFileAbsolute -Force -ErrorAction SilentlyContinue > $null
    }
}

  $decompressScript = @'
use strict;
use warnings;
use Win32::LongPath qw(openL);
use Compress::Raw::Zlib;

my ($infile, $outfile) = @ARGV;
my ($in, $out);

openL($in,  '<:raw', $infile)  or die "Cannot openL (read) '$infile': $!";
die "FATAL: Failed to get valid input filehandle for '$infile' after openL" unless defined fileno($in) && fileno($in) >= 0;
openL($out, '>:raw', $outfile) or die "Cannot openL (write) '$outfile': $!";
die "FATAL: Failed to get valid output filehandle for '$outfile' after openL" unless defined fileno($out) && fileno($out) >= 0;

my $sig;
read($in, $sig, 8) or die "Unable to read compressed file signature from handle for '$infile': $!";
if ($sig ne "\xC1\x83\x2A\x9E\x00\x00\x00\x00") { die "Bad file magic"; }
my $data;
read($in, $data, 24) or die "Unable to read compressed file header from handle for '$infile': $!";
my ($chunksizelo, $chunksizehi, $comprtotlo,  $comprtothi, $uncomtotlo,  $uncomtothi) = unpack("(LLLLLL)<", $data);
my @chunks;
my $comprused = 0;
while ($comprused < $comprtotlo) {
  read($in, $data, 16) or die "Unable to read compressed file chunk header from handle for '$infile': $!";
  my ($comprsizelo, $comprsizehi, $uncomsizelo, $uncomsizehi) = unpack("(LLLL)<", $data);
  push @chunks, $comprsizelo;
  $comprused += $comprsizelo;
}
my $inflate = Compress::Raw::Zlib::Inflate->new();
foreach my $comprsize (@chunks) {
  read($in, $data, $comprsize) or die "File read failed for chunk from handle for '$infile': $!";
  my $output;
  my $status = $inflate->inflate($data, $output, 1);
  if ($status != Z_STREAM_END) { die "Bad compressed stream; status: $status"; }
  print $out $output or die "File print failed for '$outfile': $!";
}
close $out or warn "Warning: close failed for output file handle for '$outfile': $!";
close $in or warn "Warning: close failed for input file handle for '$infile': $!";
exit 0;
'@

  $createModfileScript = @'
use strict;
use warnings;
use Win32::LongPath qw(openL);
use Encode;

my ($infile, $outfile, $game, $modid, $modname) = @ARGV;
my ($in, $out);

openL($in,  "<:raw", $infile)  or die "Cannot openL (read) '$infile': $!";
die "FATAL: Failed to get valid input filehandle for '$infile' after openL" unless defined fileno($in) && fileno($in) >= 0;
openL($out, ">:raw", $outfile) or die "Cannot openL (write) '$outfile': $!";
die "FATAL: Failed to get valid output filehandle for '$outfile' after openL" unless defined fileno($out) && fileno($out) >= 0;

my $data;
{ local $/; $data = <$in>; }
die "Failed to read data from '$infile': $!" unless defined $data;

my $mapnamelen = unpack('@0 L<', $data);
my $mapname = substr($data, 4, $mapnamelen - 1);
my $nummaps = unpack("@" . ($mapnamelen + 4) . " L<", $data);
my $pos = $mapnamelen + 8;
my $realmodname = $modname || $mapname;
my $modnamez = $realmodname . "\x00";
my $modnamelen = length($modnamez);
my $modpath = "../../../$game/Content/Mods/$modid\x00";
my $modpathlen = length($modpath);
print $out pack("L< L< L< Z$modnamelen L< Z$modpathlen L<", $modid, 0, $modnamelen, $modnamez, $modpathlen, $modpath, $nummaps) or die "File print failed for header: $!";
for (my $mapnum = 0; $mapnum < $nummaps; $mapnum++) {
  my $mapfilelen = unpack("@" . $pos . " L<", $data);
  my $mapfile_with_null = substr($data, $pos + 4, $mapfilelen);
  print $out pack("L<", $mapfilelen) or die "File print failed for map len: $!";
  print $out $mapfile_with_null or die "File print failed for map name: $!";
  $pos += 4 + $mapfilelen;
}
print $out "\x33\xFF\x22\xFF\x02\x00\x00\x00\x01" or die "File print failed for footer: $!";
close $out or warn "Warning: close failed for output file handle for '$outfile': $!";
close $in or warn "Warning: close failed for input file handle for '$infile': $!";
'@

  $decompressScriptFile = Join-Path $env:TEMP "decompress.pl"
  Set-Content -Path $decompressScriptFile -Value $decompressScript -Encoding ASCII -Force
  $createModfileScriptFile = Join-Path $env:TEMP "createModfile.pl"
  Set-Content -Path $createModfileScriptFile -Value $createModfileScript -Encoding ASCII -Force

  Get-ChildItem -Path $AbsoluteModSrcDir -Filter *.z -Recurse -File | ForEach-Object {
    $relPathWithZ = Get-RelativePath -ReferencePath $AbsoluteModSrcDir -ItemPath $_.FullName
    $relPath = $relPathWithZ -replace '\.z$', ''
    $absoluteSrcZFilePath = $_.FullName
    $absoluteDestFilePath = Join-Path $AbsoluteModDestDir $relPath

    $srcTime = $_.LastWriteTimeUtc
    $destExists = Test-Path $absoluteDestFilePath
    $needsUpdate = $true
    if ($destExists) {
        if ($srcTime -le (Get-Item $absoluteDestFilePath).LastWriteTimeUtc) {
            $needsUpdate = $false
        }
    }

    if ($needsUpdate) {
        $parentDirAbsolute = Split-Path -Path $absoluteDestFilePath -Parent
        if ($parentDirAbsolute -and (-not (Test-Path $parentDirAbsolute))) {
            New-Item -ItemType Directory -Force -Path $parentDirAbsolute > $null
        }
        perl $decompressScriptFile "$absoluteSrcZFilePath" "$absoluteDestFilePath"
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0 -and (Test-Path $absoluteDestFilePath)) {
             try {
                (Get-Item $absoluteDestFilePath).LastWriteTimeUtc = $srcTime
             } catch {
                 Write-Warning "Could not set timestamp on '$absoluteDestFilePath': $($_.Exception.Message)"
             }
        } elseif ($exitCode -ne 0) {
             Write-Host "  Warning: Perl decompression failed for '$absoluteSrcZFilePath' (Exit code: $LASTEXITCODE)."
         }
    }
  }

  $absoluteModOutputFile = Join-Path $AbsoluteModsInstallDir "$modId.mod"
  $absoluteModInfoFile = Join-Path $AbsoluteModSrcDir "mod.info"
  $absoluteModmetaFile = Join-Path $AbsoluteModSrcDir "modmeta.info"

  if (!(Test-Path $absoluteModInfoFile)) {
      Write-Host "  Error: $absoluteModInfoFile not found! Cannot generate .mod file. Skipping mod $modId."
      return
  }

  $modName = ""
  try {
    $html = Invoke-WebRequest -Uri "http://steamcommunity.com/sharedfiles/filedetails/?id=$modId" -UseBasicParsing -ErrorAction Stop -TimeoutSec 10
    $modName = ($html.Content -split '<div class="workshopItemTitle">')[1] -split '</div>' | Select-Object -First 1
    $modName = $modName.Trim()
  } catch {
      Write-Host "  Warning: Failed to fetch mod name for $modId. Using name from mod.info."
  }

  perl $createModfileScriptFile "$absoluteModInfoFile" "$absoluteModOutputFile" "ShooterGame" "$modId" "$modName"
  if ($LASTEXITCODE -ne 0) {
     Write-Host "  Error: Perl script failed to generate '$absoluteModOutputFile' (Exit code: $LASTEXITCODE)."
     Remove-Item $createModfileScriptFile -Force -ErrorAction SilentlyContinue
     return
  }

  $bytes = [System.IO.File]::ReadAllBytes($absoluteModOutputFile)
  $outputStream = New-Object System.IO.MemoryStream
  $outputStream.Write($bytes, 0, $bytes.Length)

  if (Test-Path $absoluteModmetaFile) {
      $modmetaBytes = [System.IO.File]::ReadAllBytes($absoluteModmetaFile)
      $outputStream.Write($modmetaBytes, 0, $modmetaBytes.Length)
  } else {
      $defaultFooter = [byte[]] (0x01, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x4D, 0x6F, 0x64, 0x54, 0x79, 0x70, 0x65, 0x00, 0x02, 0x00, 0x00, 0x00, 0x31, 0x00)
      $outputStream.Write($defaultFooter, 0, $defaultFooter.Length)
  }

  [System.IO.File]::WriteAllBytes($absoluteModOutputFile, $outputStream.ToArray())
  $outputStream.Close()

  $srcTime = (Get-Item $absoluteModInfoFile).LastWriteTimeUtc
  (Get-Item $absoluteModOutputFile).LastWriteTimeUtc = $srcTime
}

# --- Main Loop ---
if ($args.Length -eq 0) {
  Write-Host "No mod IDs specified"
  exit 1
}

Write-Host "Installing/updating mods..."

$modIds = $args[0] -replace '^"(.*)"$', '$1'
$modIds = $modIds.Split(',')

Setup-StrawberryPerl

foreach ($modId in $modIds) {
  Download-Mod -modId $modId
  Install-Mod -modId $modId
}

Write-Host "Mod installation/update process finished."
exit 0
