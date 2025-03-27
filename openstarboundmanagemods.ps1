Set-Location -Path "./openstarbound/server/win/mods"

$workshopDir = "../../../211820/steamapps/workshop/content/211820"

if (Test-Path $workshopDir) {
  Write-Output "Linking mods"

  Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
    $modID = $_.Name
    $pakFile = Join-Path -Path $workshopDir -ChildPath "$modID/contents.pak"

    if (Test-Path $pakFile) {
      $linkPath = "./$modID.pak"

      if (Test-Path -LiteralPath $linkPath) {
        Remove-Item -LiteralPath $linkPath -Force -Recurse
      }

      New-Item -ItemType Junction -Path $linkPath -Target $pakFile -Force | Out-Null
    } else {
      Write-Output "No contents.pak in $modID, skipping"
    }
  }
} else {
  Write-Output "No mods to link"
}

exit 0