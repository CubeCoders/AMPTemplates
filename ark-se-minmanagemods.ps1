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

  # Decompress the .z file using .NET's GzipStream class
  try {
      # Open the source .z file as an input stream
      $inputStream = [System.IO.File]::OpenRead($srcFile)
      $outputStream = [System.IO.File]::Create($destFile)

      # Create a GzipStream for decompression
      $gzipStream = New-Object System.IO.Compression.GzipStream($inputStream, [System.IO.Compression.CompressionMode]::Decompress)

      # Copy the decompressed content to the output stream
      $gzipStream.CopyTo($outputStream)

      # Close streams
      $gzipStream.Close()
      $outputStream.Close()
      $inputStream.Close()

      Write-Host "Decompressed $srcFile to $destFile"
  } catch {
      Write-Host "Error decompressing $srcFile: $($Error[0])"
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

  try {
    # Read the mod.info file content
    $modInfoContent = Get-Content -Path $modInfoFile -Raw
    $mapnamelen = [BitConverter]::ToInt32([System.Text.Encoding]::UTF8.GetBytes($modInfoContent.Substring(0, 4)), 0)
    $mapname = $modInfoContent.Substring(4, $mapnamelen - 1)
    $nummaps = [BitConverter]::ToInt32([System.Text.Encoding]::UTF8.GetBytes($modInfoContent.Substring($mapnamelen + 4, 4)), 0)

    # Create mod name and mod path (null-terminated strings)
    $modname = $modName + [char]0
    $modpath = "../../../ShooterGame/Content/Mods/" + $modInfoFile.BaseName + [char]0

    # Open the .mod file for writing in binary mode
    $modFileStream = New-Object System.IO.FileStream($modOutputFile, [System.IO.FileMode]::Create)
    $writer = New-Object System.IO.BinaryWriter($modFileStream)

    # Write header and mod info to the .mod file
    $writer.Write([BitConverter]::GetBytes($nummaps))
    $writer.Write([System.Text.Encoding]::UTF8.GetBytes($modname))
    $writer.Write([System.Text.Encoding]::UTF8.GetBytes($modpath))

    # Optionally, if there are maps, write them out (this part can be adjusted as needed for the map data)
    for ($i = 0; $i -lt $nummaps; $i++) {
        $mapfilelen = [BitConverter]::ToInt32([System.Text.Encoding]::UTF8.GetBytes($modInfoContent.Substring($mapnamelen + 8 + ($i * 4), 4)), 0)
        $mapfile = $modInfoContent.Substring($mapnamelen + 12 + ($i * $mapfilelen), $mapfilelen)
        $writer.Write([BitConverter]::GetBytes($mapfilelen))
        $writer.Write([System.Text.Encoding]::UTF8.GetBytes($mapfile))
    }

    # Write end of file signature
    $writer.Write([byte[]](0x33, 0xFF, 0x22, 0xFF, 0x02, 0x00, 0x00, 0x00, 0x01))

    # Close the file
    $writer.Close()
    $modFileStream.Close()

    Write-Host "Created .mod file: $modOutputFile"
  } catch {
      Write-Host "Error creating .mod file: $($Error[0])"
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
