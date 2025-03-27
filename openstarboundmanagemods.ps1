Set-Location -Path "./openstarbound/server/mods"

$workshopDir = "../../211820/steamapps/workshop/content/211820"

if (Test-Path $workshopDir) {
  Write-Output "Copying mods"

  Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
    $modID = $_.Name
    $pakFile = Join-Path -Path $workshopDir -ChildPath "$modID/contents.pak"

    if (Test-Path $pakFile) {
      $copyPath = "./$modID.pak"

      if (Test-Path -LiteralPath $copyPath) {
        Remove-Item -LiteralPath $copyPath -Force
      }

      Copy-Item -Path $pakFile -Destination $copyPath -Force | Out-Null
    } else {
      Write-Output "No contents.pak in $modID, skipping"
    }
  }
} else {
  Write-Output "No mods to copy"
}

exit 0
