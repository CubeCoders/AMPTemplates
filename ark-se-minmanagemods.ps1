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
    $output = & ./steamcmd.exe +force_install_dir 376030 +login anonymous +workshop_download_item 346110 $modId validate +quit 2>&1
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
  Get-ChildItem -Path $modSrcDir -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $destDir = "$modDestDir\$($_.FullName.Substring($modSrcDir.Length))"
    New-Item -ItemType Directory -Force -Path $destDir
  }

  # Remove files in destination not present in source
  Get-ChildItem -Path $modDestDir -File -ErrorAction SilentlyContinue | ForEach-Object {
    $file = $_.FullName.Substring($modDestDir.Length + 1)
    if (-not (Test-Path "$modSrcDir\$file") -and -not (Test-Path "$modSrcDir\$file.z")) {
      Remove-Item "$modDestDir\$file"
    }
  }

  # Remove empty directories in destination
  Get-ChildItem -Path $modDestDir -Directory -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $dir = $_.FullName.Substring($modDestDir.Length + 1)
    if (-not (Test-Path "$modSrcDir\$dir")) {
      Remove-Item $_.FullName -Recurse
    }
  }

  # Hardlink regular files
  Get-ChildItem -Path $modSrcDir -File -ErrorAction SilentlyContinue | ForEach-Object {
    $srcFile = $_.FullName
    $destFile = Join-Path $modDestDir $_.Name
    if (-not (Test-Path $destFile) -or (Get-Item $srcFile).LastWriteTime -gt (Get-Item $destFile).LastWriteTime) {
    New-Item -ItemType HardLink -Path $destFile -Target $srcFile
    }
  }

  # Decompress the .z file using .NET's GzipStream class
  Get-ChildItem -Path $modSrcDir -File -Filter "*.z" -ErrorAction SilentlyContinue | ForEach-Object {
    $srcFile = $_.FullName
    $destFile = "$modDestDir\$($_.Name.Substring(0, $_.Name.Length - 2))"
    
    # Check if the destination file doesn't exist or the source file is newer
    if (-not (Test-Path $destFile) -or (Get-Item $srcFile).LastWriteTime -gt (Get-Item $destFile).LastWriteTime) {
        
        # Open the .z file
        $srcFileStream = [System.IO.File]::OpenRead($srcFile)
        
        # Read the magic signature (8 bytes)
        $signature = New-Object byte[] 8
        $srcFileStream.Read($signature, 0, 8)

        # Validate the signature
        if ($signature -ne [byte[]]@(0xC1, 0x83, 0x2A, 0x9E, 0x00, 0x00, 0x00, 0x00)) {
            throw "Bad file magic"
        }

        # Read the next 24 bytes of data
        $data = New-Object byte[] 24
        $srcFileStream.Read($data, 0, 24)

        # Unpack the data (similar to Perl unpack)
        $chunksizelo = [BitConverter]::ToUInt32($data, 0)
        $chunksizehi = [BitConverter]::ToUInt32($data, 4)
        $comprtotlo = [BitConverter]::ToUInt32($data, 8)
        $comprtothi = [BitConverter]::ToUInt32($data, 12)
        $uncomtotlo = [BitConverter]::ToUInt32($data, 16)
        $uncomtothi = [BitConverter]::ToUInt32($data, 20)

        # Initialize variables
        $chunks = @()
        $comprused = 0

        # Process each chunk size
        while ($comprused -lt $comprtotlo) {
            $chunkData = New-Object byte[] 16
            $srcFileStream.Read($chunkData, 0, 16)

            $comprsizelo = [BitConverter]::ToUInt32($chunkData, 0)
            $comprsizehi = [BitConverter]::ToUInt32($chunkData, 4)
            $uncomsizelo = [BitConverter]::ToUInt32($chunkData, 8)
            $uncomsizehi = [BitConverter]::ToUInt32($chunkData, 12)
            
            # Add the chunk size to the list
            $chunks += $comprsizelo
            $comprused += $comprsizelo
        }

        # Process the chunks and decompress
        foreach ($comprsize in $chunks) {
            $chunkData = New-Object byte[] $comprsize
            $srcFileStream.Read($chunkData, 0, $comprsize)

            # Inflate (decompress) using System.IO.Compression
            $inflater = New-Object System.IO.Compression.DeflateStream([System.IO.MemoryStream]::new($chunkData), [System.IO.Compression.CompressionMode]::Decompress)
            $outputStream = [System.IO.MemoryStream]::new()

            $inflater.CopyTo($outputStream)

            # Get decompressed data
            $output = $outputStream.ToArray()

            # Write decompressed data to the destination file
            [System.IO.File]::WriteAllBytes($destFile, $output)
        }

        # Close the source file stream
        $srcFileStream.Close()

        # Preserve the timestamp (CreationTimeUtc)
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

  # Read the file content
  $data = Get-Content -Path $modInfoFile -Raw -AsByteStream

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
Set-Location -Path './arkse'

foreach ($modId in $modIds) {
  Download-Mod -modId $modId
  Install-Mod -modId $modId
}

Write-Host "Mod installation/update process finished."
exit 0
