$List = ampinstmgr -l

$ADSFound = ''
$ADSPath = ''
$InstanceName = ''
$i = 0
Foreach ($Line in $List)
{
    If ($Line -match 'Module.*ADS')
    {
        $ADSFound = 'Y'
    }
    
    If ($ADSFound -eq 'Y' -and $Line -match 'Instance Name.*')
    {
        $InstanceName = $Line.Substring(21)
    }

    If ($ADSFound -eq 'Y' -and $Line -match 'Data Path.*')
    {
        $ADSPath = $Line.Substring(21)
    }

    If ($InstanceName -and $ADSPath)
    {
        break
    }

    $i++
}


$TemplatesPath = $ADSPath + "\Plugins\ADSModule\GenericTemplates"
$ZipPath = $TemplatesPath + "\AMPTemplates-main"

Write-Output "ADS Instance Name $InstanceName"
Write-Output "ADS Path $ADSPath"
Write-Output "Change directory to $TemplatesPath"
cd "$TemplatesPath"

Write-Output "Downloading AMPTemplates repo"
Invoke-WebRequest 'https://github.com/CubeCoders/AMPTemplates/archive/refs/heads/main.zip' -OutFile .\amptemplates.zip

Write-Output "Extracting downloaded zip file"
Expand-Archive .\amptemplates.zip .\ -Force

Write-Output "Deleting downloaded zip file"
Remove-Item .\amptemplates.zip -Force

Write-Output "Moving files into main template directory"
Get-ChildItem -Path $ZipPath -Recurse -File | Move-Item -Destination $TemplatesPath -Force

Write-Output "Removing unnecessary items"
Remove-Item $TemplatesPath\*.md -Force
Remove-Item $ZipPath -Recurse -Force

Write-Output "Restarting $InstanceName"
ampinstmgr -r $InstanceName