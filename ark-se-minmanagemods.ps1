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
    Write-Host "  Error: Failed to install required Perl modules $requiredPerlModules."
    return $false
  }

  return $true
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

# Function to extract and install downloaded mod files
function Install-Mod {
  param (
    [string]$modId
  )

  Set-Location -Path "$PSScriptRoot\arkse\376030"

  $workshopContentDir = "steamapps\workshop\content\346110"
  $modsInstallDir = "ShooterGame\Content\Mods"
  $modDestDir = Join-Path $modsInstallDir $modId
  $modSrcToplevelDir = Join-Path $workshopContentDir $modId
  $modSrcDir = ""
  $modInfoFile = ""
  $modOutputFile = ""
  $modmetaFile = ""
  $modName = ""

  if (-not (Test-Path $modDestDir)) {
    New-Item -ItemType Directory -Force -Path $modDestDir > $null
  }

  $potentialSrcDir = Join-Path $modSrcToplevelDir "WindowsNoEditor"
  if (-not (Test-Path $potentialSrcDir)) {
    $modInfoCheckPath = Join-Path $modSrcToplevelDir "mod.info"
    if (Test-Path $modInfoCheckPath) {
      $modSrcDir = $modSrcToplevelDir
    } else {
      Write-Host "  Error: Mod source directory not found for branch Windows in $modSrcToplevelDir. Cannot find mod.info. Skipping mod $modId."
      return
    }
  } else {
    $modSrcDir = $potentialSrcDir
    $modInfoCheckPath = Join-Path $modSrcDir "mod.info"
    if (-not (Test-Path $modInfoCheckPath)) {
      Write-Host "  Error: Found branch directory $modSrcDir, but it's missing mod.info. Skipping mod $modId."
      return
    }
  }

  $modSrcDirResolved = Resolve-Path -Path $modSrcDir -ErrorAction SilentlyContinue
  $modDestDirResolved = Resolve-Path -Path $modDestDir -ErrorAction SilentlyContinue
  if (-not $modSrcDirResolved -or -not $modDestDirResolved) {
     Write-Host "  Error: Could not resolve base paths '$modSrcDir' or '$modDestDir'. Skipping mod $modId."
     return
  }

  # Helper function for robust relative path calculation using .NET Uri
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

  Get-ChildItem -Path $modSrcDir -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $relativeDirPath = Get-RelativePath -ReferencePath $modSrcDirResolved.Path -ItemPath $_.FullName
    $destDirRelative = Join-Path $modDestDir $relativeDirPath
    if (-not (Test-Path $destDirRelative)) {
      New-Item -ItemType Directory -Force -Path $destDirRelative > $null
    }
  }

  Get-ChildItem -Path $modDestDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $relPath = Get-RelativePath -ReferencePath $modDestDirResolved.Path -ItemPath $_.FullName
    $srcFileRelative = Join-Path $modSrcDir $relPath
    $srcZFileRelative = "$srcFileRelative.z"
    if (-not (Test-Path $srcFileRelative) -and -not (Test-Path $srcZFileRelative)) {
      $destFileToRemove = Join-Path $modDestDir $relPath
      Remove-Item -Path $destFileToRemove -Force -ErrorAction SilentlyContinue > $null
    }
  }

  Get-ChildItem -Path $modDestDir -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $dirRelPath = Get-RelativePath -ReferencePath $modDestDirResolved.Path -ItemPath $_.FullName
    $srcDirPath = Join-Path $modSrcDir $dirRelPath
    $destDirPath = Join-Path $modDestDir $dirRelPath
    if (-not (Test-Path $srcDirPath)) {
      Remove-Item -Path $destDirPath -Recurse -Force -ErrorAction SilentlyContinue > $null
    }
  }
  Get-ChildItem -Path $modDestDir -Directory -Recurse -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
      $dirRelPath = Get-RelativePath -ReferencePath $modDestDirResolved.Path -ItemPath $_.FullName
      $destDirPath = Join-Path $modDestDir $dirRelPath
      if ((Get-ChildItem -Path $destDirPath -ErrorAction SilentlyContinue).Count -eq 0) {
         Remove-Item -Path $destDirPath -Force -ErrorAction SilentlyContinue > $null
      }
  }

  Get-ChildItem -Path $modSrcDir -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notlike '*.z' -and $_.Name -notlike '*.z.uncompressed_size'
  } | ForEach-Object {
    $relPath = Get-RelativePath -ReferencePath $modSrcDirResolved.Path -ItemPath $_.FullName
    $srcFileRelative = Join-Path $modSrcDir $relPath
    $destFileRelative = Join-Path $modDestDir $relPath

    $needsLink = $true
    if (Test-Path $destFileRelative) {
       if ((Get-Item $srcFileRelative).LastWriteTimeUtc -le (Get-Item $destFileRelative).LastWriteTimeUtc) {
           $needsLink = $false
       } else {
           Remove-Item -Path $destFileRelative -Force > $null
       }
    }
    if ($needsLink) {
        $parentDirRelative = Split-Path -Path $destFileRelative -Parent
        if ($parentDirRelative -and (-not (Test-Path $parentDirRelative))) {
            New-Item -ItemType Directory -Force -Path $parentDirRelative > $null
        }
        New-Item -ItemType HardLink -Path $destFileRelative -Target $srcFileRelative -Force -ErrorAction SilentlyContinue > $null
    }
}

  $decompressScript = @'
use Compress::Raw::Zlib;
use Win32::LongPath qw(openL);

my ($infile, $outfile) = @ARGV;

my ($in, $out);

my $ok_in = openL(\$in, '<:raw', $infile);
die "Cannot openL '$infile': $!" unless $ok_in && defined $in && defined fileno($in) && fileno($in) >= 0;

my $ok_out = openL(\$out, '>:raw', $outfile);
die "Cannot openL '$outfile': $!" unless $ok_out && defined $out && defined fileno($out) && fileno($out) >= 0;

my $sig;
read($in, $sig, 8) or die "Unable to read compressed file: $!";
if ($sig != "\xC1\x83\x2A\x9E\x00\x00\x00\x00"){
  die "Bad file magic";
}

my $data;
read($in, $data, 24) or die "Unable to read compressed file: $!";
my ($chunksizelo, $chunksizehi,
    $comprtotlo, $comprtothi,
    $uncomtotlo, $uncomtothi) = unpack("(LLLLLL)<", $data);

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
  print $output;
}

close($out);
close($in);
exit 0;
'@

  $createModfileScript = @'
use strict;
use warnings;
use Win32::LongPath qw(openL);
use Encode;

my ($infile, $outfile, $game, $modid, $modname) = @ARGV;
my ($in, $out);

my $inok = openL($in, "<:raw", $infile);
die "Cannot openL (read) '$infile': $!" unless $inok && defined $in && defined fileno($in) && fileno($in) >= 0;
my $outok = openL($out, ">:raw", $outfile);
die "Cannot openL (write) '$outfile': $!" unless $outok && defined $out && defined fileno($out) && fileno($out) >= 0;

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

  Get-ChildItem -Path $modSrcDir -Filter *.z -Recurse -File | ForEach-Object {
    $relPathWithZ = Get-RelativePath -ReferencePath $modSrcDirResolved.Path -ItemPath $_.FullName
    $srcFileRelative = Join-Path $modSrcDir $relPathWithZ
    $relPath = $relPathWithZ -replace '\.z$', ''
    $destFileRelative = Join-Path $modDestDir $relPath

    $srcTime = $_.LastWriteTimeUtc
    $destExists = Test-Path $destFileRelative
    $needsUpdate = $true
    if ($destExists) {
        if ($srcTime -le (Get-Item $destFileRelative).LastWriteTimeUtc) {
            $needsUpdate = $false
        }
    }

    if ($needsUpdate) {
      $parentDirRelative = Split-Path -Path $destFileRelative -Parent
      if ($parentDirRelative -and (-not (Test-Path $parentDirRelative))) {
          New-Item -ItemType Directory -Force -Path $parentDirRelative > $null
      }
  
      $srcFileAbsolute = Join-Path "$PSScriptRoot\arkse\376030" "$srcFileRelative"
      $destFileAbsolute = Join-Path "$PSScriptRoot\arkse\376030" "$destFileRelative"

      perl $decompressScriptFile "$srcFileAbsolute" "$destFileAbsolute"
      if ($LASTEXITCODE -eq 0 -and (Test-Path $destFileRelative)) {
          (Get-Item $destFileRelative).LastWriteTimeUtc = $srcTime
      } elseif ($LASTEXITCODE -ne 0) {
           Write-Host "  Warning: Perl decompression failed for '$srcFileAbsolute' (Exit code: $LASTEXITCODE)."
       }
    }
  }

  $modOutputFileRelative = Join-Path $modsInstallDir "$modId.mod"
  $modInfoFileRelative = Join-Path $modSrcDir "mod.info"
  $modmetaFileRelative = Join-Path $modSrcDir "modmeta.info"

  if (!(Test-Path $modInfoFileRelative)) {
      Write-Host "  Error: $modInfoFileRelative not found! Cannot generate .mod file. Skipping mod $modId."
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

  $createModfileScriptFile = Join-Path $env:TEMP "createModfile.pl"
  Set-Content -Path $createModfileScriptFile -Value $createModfileScript -Encoding ASCII -Force
  perl $createModfileScriptFile "$modInfoFileRelative" "$modOutputFileRelative" "ShooterGame" "$modId" "$modName"
  if ($LASTEXITCODE -ne 0) {
     Write-Host "  Error: Perl script failed to generate '$modOutputFileRelative' (Exit code: $LASTEXITCODE)."
     return
  }

  $modOutputFileResolved = Resolve-Path $modOutputFileRelative
  $bytes = [System.IO.File]::ReadAllBytes($modOutputFileResolved.Path)
  $outputStream = New-Object System.IO.MemoryStream
  $outputStream.Write($bytes, 0, $bytes.Length)

  if (Test-Path $modmetaFileRelative) {
      $modmetaFileResolved = Resolve-Path $modmetaFileRelative
      $modmetaBytes = [System.IO.File]::ReadAllBytes($modmetaFileResolved.Path)
      $outputStream.Write($modmetaBytes, 0, $modmetaBytes.Length)
  } else {
      $defaultFooter = [byte[]] (0x01, 0x00, 0x00, 0x00,
                                0x08, 0x00, 0x00, 0x00,
                                0x4D, 0x6F, 0x64, 0x54, 0x79, 0x70, 0x65, 0x00,
                                0x02, 0x00, 0x00, 0x00,
                                0x31, 0x00)
      $outputStream.Write($defaultFooter, 0, $defaultFooter.Length)
  }

  [System.IO.File]::WriteAllBytes($modOutputFileResolved.Path, $outputStream.ToArray())
  $outputStream.Close()

  $srcTime = (Get-Item $modInfoFileRelative).LastWriteTimeUtc
  (Get-Item $modOutputFileRelative).LastWriteTimeUtc = $srcTime
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
    Download-Mod -modId $modId
    Install-Mod -modId $modId
  }
}

Write-Host "Mod installation/update process finished."
exit 0