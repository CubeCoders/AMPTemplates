Set-Location -Path "./openstarbound/server/mods"

$workshopDir = "../../211820/steamapps/workshop/content/211820"

if (Test-Path $workshopDir) {
    Write-Output "Copying mods"

    Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
        $modID = $_.Name
        $modPath = Join-Path -Path $workshopDir -ChildPath $modID

        $pakFiles = Get-ChildItem -Path $modPath -Filter *.pak -File -ErrorAction SilentlyContinue

        if ($pakFiles.Count -eq 0) {
            Write-Output "No .pak file in $modID, skipping"
            return
        }

        for ($i = 0; $i -lt $pakFiles.Count; $i++) {
            if ($i -eq 0) {
                $targetName = "$modID.pak"
            } else {
                $suffix = $i + 1
                $targetName = "${modID}_$suffix.pak"
            }

            Copy-Item -Path $pakFiles[$i].FullName -Destination "./$targetName" -Force | Out-Null
        }
    }
} else {
    Write-Output "No mods to copy"
}

exit 0
