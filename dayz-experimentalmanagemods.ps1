$ModDirFormat = $args[0]

Set-Location -Path "./dayz/1042420"

if (Test-Path -Path "./steamapps/workshop/content/221100") {
    if ($ModDirFormat -eq "false") {
        # Remove junctions corresponding to actual directories
        Get-ChildItem -Path "./steamapps/workshop/content/221100" -Directory | ForEach-Object {
            $modName = (Select-String -Path "$($_.FullName)/meta.cpp" -Pattern '^\s*name\s*=\s*"(.*)"' | ForEach-Object { $_.Matches.Groups[1].Value })[0]
            Remove-Item -Path "./@$modName" -Force -ErrorAction SilentlyContinue
        }
        # Create junction links for numbered directories
        Get-ChildItem -Path "./steamapps/workshop/content/221100" -Directory | ForEach-Object {
            New-Item -ItemType Junction -Name "$($_.Name)" -Target $_.FullName -Force
        }
    } else {
        # Remove numbered junctions corresponding to the directories
        Get-ChildItem -Path "./steamapps/workshop/content/221100" -Directory | ForEach-Object {
            Remove-Item -Path "./$($_.Name)" -Force -ErrorAction SilentlyContinue
        }
        # Create @name junctions for directories based on mod.cpp
        Get-ChildItem -Path "./steamapps/workshop/content/221100" -Directory | ForEach-Object {
            $modName = (Select-String -Path "$($_.FullName)/meta.cpp" -Pattern '^\s*name\s*=\s*"(.*)"' | ForEach-Object { $_.Matches.Groups[1].Value })[0]
            New-Item -ItemType Junction -Name "@$modName" -Target $_.FullName -Force
        }
    }
}

Exit 0