$ModDirFormat = $args[0]

Set-Location -Path ".\dayz\1042420"

$workshopDir = ".\steamapps\workshop\content\221100"

if (Test-Path $workshopDir) {
    if ($ModDirFormat -eq "false") {
        # Remove @name symlinks corresponding to the mod directories based on meta.cpp
        Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
            $modDir = $_.FullName
            $modName = (Select-String -Path "$modDir\meta.cpp" -Pattern '^\s*name\s*=\s*"(.*)"' -AllMatches).Matches.Groups[1].Value
            if ($modName) {
                $symlinkName = "@$modName"
                if (Test-Path $symlinkName) {
                    Remove-Item -Path $symlinkName -Force -Recurse
                }
            }
        }
        # Create numbered symlinks for the mod directories
        Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
            if (Test-Path $_.Name) {
                Remove-Item -Path $_.Name -Force -Recurse
            }
            New-Item -ItemType Junction -Name $_.Name -Target $_.FullName -Force | Out-Null
        }
    }
    else {
        # Remove numbered symlinks for the mod directories
        Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
            if (Test-Path $_.Name) {
                Remove-Item -Path $_.Name -Force -Recurse
            }
        }
        # Create @name symlinks for the mod directories based on meta.cpp
        Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
            $modDir = $_.FullName
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
