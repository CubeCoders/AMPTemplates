[string]$ADS = ampinstmgr -i ADS | Select-String -Pattern "Data Path"
$ADSPath = $ADS.Substring(21)
$TemplatesPath = $ADSPath + "\Plugins\ADSModule\GenericTemplates"
$ZipPath = $TemplatesPath + "\AMPTemplates-main"

Write-Output "ADS Path $ADS"
Write-Output "Change directory to $TemplatesPath"
cd "$TemplatesPath"

Write-Output "Downloading AMPTemplates GH"
Invoke-WebRequest 'https://github.com/CubeCoders/AMPTemplates/archive/refs/heads/main.zip' -OutFile .\amptemplates.zip

Write-Output "Extracting downloaded zip file"
Expand-Archive .\amptemplates.zip .\ -Force

Write-Output "Deleting downloaded zip file"
Remove-Item .\amptemplates.zip

Write-Output "Moving files into main template directory"
Get-ChildItem -Path $ZipPath -Recurse -File | Move-Item -Destination $TemplatesPath -Force

Write-Output "Removing unnecessary items"
Remove-Item $TemplatesPath\*.md -Force
Remove-Item $ZipPath -Recurse -Force

Write-Output "Restarting ADS"
ampinstmgr -r ADS