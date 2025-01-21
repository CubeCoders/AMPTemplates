$ModDirFormat = $args[0]

Set-Location -Path ".\dayz\1042420"

$workshopDir = ".\steamapps\workshop\content\221100"

if (Test-Path $workshopDir) {
    if ($ModDirFormat -eq "false") {
        Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
            $modDir = Join-Path -Path $workshopDir -ChildPath $_.Name
            $modName = (Select-String -Path "$modDir\meta.cpp" -Pattern '^\s*name\s*=\s*"(.*)"' -AllMatches).Matches.Groups[1].Value
            # Remove @name junction links corresponding to the mod directories based on meta.cpp
            if ($modName) {
                $symlinkName = "@$modName"
                if (Test-Path $symlinkName) {
                    Remove-Item -Path $symlinkName -Force -Recurse
                }
            }
            # Create numbered junction links for the mod directories
            if (Test-Path $_.Name) {
                Remove-Item -Path $_.Name -Force -Recurse
            }
            New-Item -ItemType Junction -Name $_.Name -Target $modDir -Force | Out-Null
        }
    }
    else {

        Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
            # Remove numbered junction links for the mod directories
            if (Test-Path $_.Name) {
                Remove-Item -Path $_.Name -Force -Recurse
            }

            # Create @name junction links for the mod directories based on meta.cpp
            $modDir = Join-Path -Path $workshopDir -ChildPath $_.Name
            $modName = (Select-String -Path "$modDir\meta.cpp" -Pattern '^\s*name\s*=\s*"(.*)"' -AllMatches).Matches.Groups[1].Value
            if ($modName) {
                $symlinkName = "@$modName"
                if (Test-Path $symlinkName) {
                    Remove-Item -Path $symlinkName -Force -Recurse
                }
                New-Item -ItemType Junction -Name $symlinkName -Target $modDir -Force | Out-Null
            }
        }
    }
}
