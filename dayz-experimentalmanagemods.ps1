param(
    [string]$ModDirFormat
)

# Change directory to the mod directory
Set-Location -Path ".\dayz\1042420"

# Check if the steamapps directory exists
$workshopDir = ".\steamapps\workshop\content\221100"
if (Test-Path $workshopDir) {
    if ($ModDirFormat -eq "false") {
        # Remove symlinks corresponding to the mod directories
        Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
            $modDir = $_.FullName
            # Capture mod name from meta.cpp file
            $modName = (Select-String -Path "$modDir\meta.cpp" -Pattern '^\s*name\s*=\s*"(.*)"' -AllMatches).Matches.Groups[1].Value
            if ($modName) {
                $symlinkPath = ".\@$modName"
                if (Test-Path $symlinkPath) {
                    Remove-Item -Path $symlinkPath -Force
                }
            }
        }
        # Create traditional symlinks for numbered directories
        Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
            New-Item -ItemType Junction -Name $_.Name -Target $_.FullName -Force | Out-Null
        }
    }
    else {
        # Remove numbered symlinks corresponding to the mod directories
        Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
            $symlinkPath = ".\$($_.Name)"
            if (Test-Path $symlinkPath) {
                Remove-Item -Path $symlinkPath -Force
            }
        }
        # Create @name symlinks for directories based on meta.cpp
        Get-ChildItem -Path $workshopDir -Directory | ForEach-Object {
            $modDir = $_.FullName
            # Capture mod name from meta.cpp file (updated regex)
            $modName = (Select-String -Path "$modDir\meta.cpp" -Pattern '^\s*name\s*=\s*"(.*)"' -AllMatches).Matches.Groups[1].Value
            if ($modName) {
                $symlinkName = "@$modName"
                New-Item -ItemType Junction -Name $symlinkName -Target $modDir -Force | Out-Null
            }
        }
    }
}
