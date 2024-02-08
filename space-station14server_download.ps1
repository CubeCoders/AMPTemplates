cd "$PSScriptRoot\space-station14\server"

# Download the manifest JSON file and convert it to a PowerShell object
$Manifest = Invoke-WebRequest -UseBasicParsing -Uri "https://cdn.centcomm.spacestation14.com/builds/wizards/manifest.json" | ConvertFrom-Json

# Find the last build key
$LastBuildKey = ($Manifest.builds | Get-Member -MemberType NoteProperty | Select-Object -Last 1).Name

# Get the download URL from the last build
$DownloadUrl = $Manifest.builds.$LastBuildKey.server."win-x64".url

# Download, extract and clean up
Invoke-WebRequest -UseBasicParsing -Uri $DownloadUrl -OutFile "SS14.Server_win-x64.zip"
Expand-Archive -Path "SS14.Server_win-x64.zip" -DestinationPath . -Force
Remove-Item "SS14.Server_win-x64.zip"
