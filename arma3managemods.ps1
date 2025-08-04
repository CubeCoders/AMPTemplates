$ModDirFormat = $args[0]

Set-Location -Path ".\arma3\233780"

$workshopDir = ".\steamapps\workshop\content\107410"

if (Test-Path $workshopDir) {
  Write-Output "Linking mods"
  Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
    $modDir = Join-Path -Path $workshopDir -ChildPath $_.Name
    $modName = $null

    # Extract modName from meta.cpp
    $metaCppPath = Join-Path -Path $modDir -ChildPath "meta.cpp"
    if (Test-Path $metaCppPath) {
      $metaMatch = Select-String -Path $metaCppPath -Pattern '^\s*name\s*=\s*"(.*?)"' -AllMatches
      if ($metaMatch.Matches.Count -gt 0) {
        $modName = $metaMatch.Matches[0].Groups[1].Value
      }
    }
    
    if (-not $modName) {
      # Fallback: Try mod.cpp if meta.cpp does not contain a name
      $modCppPath = Join-Path -Path $modDir -ChildPath "mod.cpp"
      if (Test-Path $modCppPath) {
        $modMatch = Select-String -Path $modCppPath -Pattern '^\s*name\s*=\s*"(.*?)"' -AllMatches
        if ($modMatch.Matches.Count -gt 0) {
          $modName = $modMatch.Matches[0].Groups[1].Value
        }
      }
      
      if (-not $modName) {
        # Final fallback: Try fetching name from Steam workshop webpage if no name found
        $modID = $_.Name
        $steamPage = "https://steamcommunity.com/workshop/filedetails/?id=$modID"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $modName = (Invoke-WebRequest -UseBasicParsing -Uri $steamPage).Content |
                   Select-String -Pattern '<div class="workshopItemTitle">([^<]*)</div>' |
                   ForEach-Object { $_.Matches.Groups[1].Value } |
                   Select-Object -First 1
        
        if (-not $modName) {
          Write-Output "Error: Unable to retrieve name for workshop item $modID. Skipping"
          return
        }
      }
    }
    
    # Sanitize modName
    $modName = $modName -replace '[\\/:*?"<>|]', '-'
    
    if ($ModDirFormat -eq "false") {
      # Remove @name junction links
      $symlinkName = Join-Path -Path "./" -ChildPath "@$modName"
      if (Test-Path -LiteralPath $symlinkName) {
        Remove-Item -LiteralPath $symlinkName -Force -Recurse
      }
      
      # Create numbered junction links
      $numLink = Join-Path -Path "./" -ChildPath $_.Name
      if (Test-Path -LiteralPath $numLink) {
        Remove-Item -LiteralPath $numLink -Force -Recurse
      }
      New-Item -ItemType Junction -Name $_.Name -Target $modDir -Force | Out-Null
    } else {
      # Remove numbered junction links
      $numLink = Join-Path -Path "./" -ChildPath $_.Name
      if (Test-Path -LiteralPath $numLink) {
        Remove-Item -LiteralPath $numLink -Force -Recurse
      }
      
      # Create @name junction links
      $symlinkName = Join-Path -Path "./" -ChildPath "@$modName"
      if (Test-Path -LiteralPath $symlinkName) {
        Remove-Item -LiteralPath $symlinkName -Force -Recurse
      }
      New-Item -ItemType Junction -Name $symlinkName -Target $modDir -Force | Out-Null
    }
  }
} else {
  Write-Output "No mods to link"
}

exit 0