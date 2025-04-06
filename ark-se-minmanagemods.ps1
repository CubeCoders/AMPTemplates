Set-Location -Path ".\arkse\376030"

$workshopDir = ".\steamapps\workshop\content\346110"
$modsInstallDir = ".\ShooterGame\Content\Mods"

if (Test-Path $workshopDir) {
  Write-Output "Installing mods..."
  Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
    $modID = $_.Name
    $modExtractDir = $_.FullName
    $modInfoPath = Join-Path $modExtractDir "mod.info"
    $modMetaPath = Join-Path $modExtractDir "modmeta.info"
    $modOutputPath = Join-Path $modsInstallDir "$modID.mod"
    $sourceDir = Join-Path $modExtractDir "WindowsNoEditor"
    $targetDir = Join-Path $modsInstallDir $modID

    if (-not (Test-Path $modInfoPath)) {
      Write-Warning "Missing mod.info for $modID"
      continue
    }

    if (-not (Test-Path $sourceDir)) {
      Write-Warning "Missing WindowsNoEditor directory for $modID"
      continue
    }

    if (Test-Path $modOutputPath) {
      Remove-Item -Force $modOutputPath
    }

    # Read mod.info
    $data = [System.IO.File]::ReadAllBytes($modInfoPath)
    $reader = New-Object System.IO.BinaryReader([System.IO.MemoryStream]::new($data))
    $writer = New-Object System.IO.BinaryWriter([System.IO.File]::OpenWrite($modOutputPath))

    # Parse mod.info structure
    $mapNameLen = $reader.ReadInt32()
    $mapNameBytes = $reader.ReadBytes($mapNameLen - 1)
    $reader.ReadByte() | Out-Null # consume null byte
    $mapName = [System.Text.Encoding]::ASCII.GetString($mapNameBytes)
    $numMaps = $reader.ReadInt32()

    # Build .mod content
    $modName = $null
    try {
      $steamPage = "https://steamcommunity.com/workshop/filedetails/?id=$modID"
      $modName = (Invoke-WebRequest -UseBasicParsing -Uri $steamPage -ErrorAction Stop).Content |
        Select-String -Pattern '<div class="workshopItemTitle">([^<]*)</div>' |
        ForEach-Object { $_.Matches.Groups[1].Value } |
        Select-Object -First 1
    } catch {
      $modName = $mapName
    }

    $modNameBytes = [System.Text.Encoding]::ASCII.GetBytes($modName)
    $modNameBytesWithNull = $modNameBytes + 0
    $modPath = "..\..\..\ShooterGame\Content\Mods\$modID"
    $modPathBytes = [System.Text.Encoding]::ASCII.GetBytes($modPath)
    $modPathBytesWithNull = $modPathBytes + 0

    $writer.Write($modIDInt)
    $writer.Write(0) # ModType = 0
    $writer.Write($modNameBytesWithNull.Length)
    $writer.Write($modNameBytesWithNull)
    $writer.Write($modPathBytesWithNull.Length)
    $writer.Write($modPathBytesWithNull)
    $writer.Write($numMaps)

    for ($i = 0; $i -lt $numMaps; $i++) {
      $mapFileLen = $reader.ReadInt32()
      $mapFileBytes = $reader.ReadBytes($mapFileLen)
      $writer.Write($mapFileLen)
      $writer.Write($mapFileBytes)
    }

    # Footer
    $footer = [byte[]](0x33, 0xFF, 0x22, 0xFF, 0x02, 0x00, 0x00, 0x00, 0x01)
    $writer.Write($footer)

    # modmeta.info or fallback
    if (Test-Path $modMetaPath) {
      $metaBytes = [System.IO.File]::ReadAllBytes($modMetaPath)
      $writer.Write($metaBytes)
    } else {
      $fallbackBytes = [byte[]](
        0x01, 0x00, 0x00, 0x00, # count
        0x08, 0x00, 0x00, 0x00, # length of key "ModType"
        0x4D, 0x6F, 0x64, 0x54, 0x79, 0x70, 0x65, 0x00, # "ModType\0"
        0x02, 0x00, 0x00, 0x00, # type = int
        0x31, 0x00              # value = "1\0"
      )
      $writer.Write($fallbackBytes)
    }

    $reader.Close()
    $writer.Close()

    # Create junction
    if (Test-Path -LiteralPath $targetDir) {
      Remove-Item -LiteralPath $targetDir -Force -Recurse
    }
    New-Item -ItemType Junction -Path $targetDir -Target $sourceDir -Force | Out-Null

    Write-Output "Installed mod: $modID ($modName)"
  }
} else {
  Write-Output "No mods to install"
}

exit 0
