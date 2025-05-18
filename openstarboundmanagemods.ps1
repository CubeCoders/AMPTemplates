Set-Location -Path "./openstarbound/server/mods"

$workshopDir = "../../211820/steamapps/workshop/content/211820"

if (Test-Path $workshopDir) {
  Write-Output "Copying mods"

  Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
    $modID = $_.Name
    $modPath = Join-Path -Path $workshopDir -ChildPath $modID

    $pakFile = Get-ChildItem -Path $modPath -Filter *.pak -File -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($pakFile) {
      $copyPath = "./$modID.pak"
      Copy-Item -Path $pakFile.FullName -Destination $copyPath -Force | Out-Null
    } else {
      Write-Output "No .pak file in $modID, skipping"
    }
  }
} else {
  Write-Output "No mods to copy"
}

exit 0
