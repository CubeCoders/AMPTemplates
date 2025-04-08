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

# Install SharpZipLib for .NET 4.5+ to handle .z files
$libDir = Join-Path $PSScriptRoot 'SharpZipLib'
$ziplibDll = Join-Path $libDir 'lib\net45\ICSharpCode.SharpZipLib.dll'
if (-not (Test-Path $ziplibDll)) {
  $nupkgUrl = "https://www.nuget.org/api/v2/package/SharpZipLib/1.3.3"
  $nupkgPath = Join-Path $libDir "SharpZipLib.nupkg"
  New-Item -ItemType Directory -Force -Path $libDir | Out-Null
  Invoke-WebRequest -Uri $nupkgUrl -OutFile $nupkgPath
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkgPath, $libDir)
  Remove-Item $nupkgPath
}
Add-Type -Path $ziplibDll

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
  $modOutputFile = ""
  $modInfoFile = ""
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

  # Hardlink regular files
  Get-ChildItem -Path $modSrcDir -File -ErrorAction SilentlyContinue | ForEach-Object {
    $srcFile = $_.FullName
    $destFile = Join-Path $modDestDir $_.Name
    if (-not (Test-Path $destFile) -or (Get-Item $srcFile).LastWriteTime -gt (Get-Item $destFile).LastWriteTime) {
      New-Item -ItemType HardLink -Path $destFile -Target $srcFile > $null
    }
  }

  # Decompress the .z file using SharpZipLib
  Get-ChildItem -Path $modSrcDir -File -Filter "*.z" -Recurse | ForEach-Object {
    $srcFile = $_.FullName
    $destFile = Join-Path $modDestDir ($_.FullName.Substring($modSrcDir.Length).TrimStart('\') -replace '\.z$', '')

    # Ensure destination directory exists
    $destDir = Split-Path $destFile
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # Skip if already extracted and up-to-date
    if (Test-Path $destFile -and (Get-Item $srcFile).LastWriteTime -le (Get-Item $destFile).LastWriteTime) {
        return
    }

    $fs = [System.IO.File]::OpenRead($srcFile)

    # Check file signature
    $signature = New-Object byte[] 8
    $fs.Read($signature, 0, 8) | Out-Null
    $expected = [byte[]](0xC1, 0x83, 0x2A, 0x9E, 0x00, 0x00, 0x00, 0x00)
    if (-not ($signature -ceq $expected)) {
        throw "Invalid file signature: $srcFile"
    }

    # Read header
    $header = New-Object byte[] 24
    $fs.Read($header, 0, 24) | Out-Null
    $chunksizelo   = [BitConverter]::ToUInt32($header, 0)
    $chunksizehi   = [BitConverter]::ToUInt32($header, 4)
    $comprtotlo    = [BitConverter]::ToUInt32($header, 8)
    $comprtothi    = [BitConverter]::ToUInt32($header, 12)
    $uncomptotlo   = [BitConverter]::ToUInt32($header, 16)
    $uncomptothi   = [BitConverter]::ToUInt32($header, 20)

    $comprused = 0
    $chunkSizes = @()

    while ($comprused -lt $comprtotlo) {
        $chunkHeader = New-Object byte[] 16
        $fs.Read($chunkHeader, 0, 16) | Out-Null

        $comprsizelo = [BitConverter]::ToUInt32($chunkHeader, 0)
        $comprsizehi = [BitConverter]::ToUInt32($chunkHeader, 4)
        $uncomsizelo = [BitConverter]::ToUInt32($chunkHeader, 8)
        $uncomsizehi = [BitConverter]::ToUInt32($chunkHeader, 12)

        $chunkSizes += @{ 
            Compressed = $comprsizelo
            Uncompressed = $uncomsizelo
        }

        $comprused += $comprsizelo
    }

    $outStream = New-Object System.IO.MemoryStream

    foreach ($chunk in $chunkSizes) {
        $chunkBytes = New-Object byte[] $chunk.Compressed
        $fs.Read($chunkBytes, 0, $chunk.Compressed) | Out-Null

        $inMem = New-Object System.IO.MemoryStream(,$chunkBytes)
        $inflater = New-Object ICSharpCode.SharpZipLib.Zip.Compression.Streams.InflaterInputStream($inMem)

        $buffer = New-Object byte[] 8192
        while (($read = $inflater.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outStream.Write($buffer, 0, $read)
        }

        $inflater.Close()
        $inMem.Close()
    }

    $fs.Close()

    # Write final decompressed content
    [System.IO.File]::WriteAllBytes($destFile, $outStream.ToArray())
    $outStream.Close()

    # Copy CreationTimeUtc from original file
    $timestamp = (Get-Item $srcFile).CreationTimeUtc
    Set-ItemProperty -Path $destFile -Name CreationTimeUtc -Value $timestamp
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

  # Read the file content
  $data = [System.IO.File]::ReadAllBytes($modInfoFile)

  # Unpack the values
  $mapnamelen = [BitConverter]::ToUInt32($data, 0)
  $mapname = [System.Text.Encoding]::ASCII.GetString($data, 4, $mapnamelen - 1)
  $nummaps = [BitConverter]::ToUInt32($data, $mapnamelen + 4)
  $pos = $mapnamelen + 8

  # Get the mod name (like $modname in Perl)
  $modname = if ($args[2]) { $args[2] } else { $mapname } + [char]0

  # Calculate modname length and modpath
  $modnamelen = $modname.Length
  $modpath = "../../../" + $args[0] + "/Content/Mods/" + $args[1] + [char]0
  $modpathlen = $modpath.Length

  # Prepare the output data for writing
  $modOutputData = New-Object System.Collections.Generic.List[byte]

  # Pack the first part
  $modOutputData.AddRange([BitConverter]::GetBytes([UInt32]$args[1]))
  $modOutputData.AddRange([BitConverter]::GetBytes(0))
  $modOutputData.AddRange([BitConverter]::GetBytes($modnamelen))
  $modOutputData.AddRange([System.Text.Encoding]::ASCII.GetBytes($modname))
  $modOutputData.AddRange([BitConverter]::GetBytes($modpathlen))
  $modOutputData.AddRange([System.Text.Encoding]::ASCII.GetBytes($modpath))
  $modOutputData.AddRange([BitConverter]::GetBytes($nummaps))

  # Process the maps
  for ($mapnum = 0; $mapnum -lt $nummaps; $mapnum++) {
    $mapfilelen = [BitConverter]::ToUInt32($data, $pos)
    $mapfile = [System.Text.Encoding]::ASCII.GetString($data, $mapnamelen + 12, $mapfilelen)

    # Pack the mapfile data
    $modOutputData.AddRange([BitConverter]::GetBytes($mapfilelen))
    $modOutputData.AddRange([System.Text.Encoding]::ASCII.GetBytes($mapfile))

    # Move to next position
    $pos += 4 + $mapfilelen
  }

  # Append the footer
  $modOutputData.AddRange([byte[]](0x33, 0xFF, 0x22, 0xFF, 0x02, 0x00, 0x00, 0x00, 0x01))

  # Write to the file
  [System.IO.File]::WriteAllBytes($modOutputFile, $modOutputData.ToArray())

  # Set timestamp of .mod file to match the mod.info file
  $timestamp = (Get-Item $modInfoFile).CreationTimeUtc
  Set-ItemProperty -Path $modOutputFile -Name CreationTimeUtc -Value $timestamp
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

foreach ($modId in $modIds) {
  Download-Mod -modId $modId
  Install-Mod -modId $modId
}

Write-Host "Mod installation/update process finished."
exit 0
