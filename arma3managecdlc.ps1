# Usage: arma3managecdlc.ps1 <depotid> <codename> <rootdir> <basedir>
# Downloads a single Arma 3 Creator DLC via its dedicated Steam depot (on the
# 'creatordlc' branch) instead of installing the full ~100GB creatordlc branch.
param(
    [Parameter(Mandatory=$true)][string]$DepotId,
    [Parameter(Mandatory=$true)][string]$Codename,
    [Parameter(Mandatory=$true)][string]$RootDir,
    [Parameter(Mandatory=$true)][string]$BaseDir
)

$ErrorActionPreference = "Stop"

$AppId = 233780
$Branch = "creatordlc"
$SteamCmd = Join-Path $RootDir "steamcmd.exe"
$AppInfo = Join-Path $RootDir "appinfo_$AppId.txt"
$DownloadDir = Join-Path $RootDir "steamapps\content\app_$AppId\depot_$DepotId"

& $SteamCmd +login anonymous +app_info_print $AppId +quit *> $AppInfo

$lines = Get-Content $AppInfo
$inDepot = $false
$depth = 0
$inBranch = $false
$gid = $null

foreach ($line in $lines) {
    if (-not $inDepot -and $line -match "^\s*`"$DepotId`"\s*$") {
        $inDepot = $true
        $depth = 0
        continue
    }
    if ($inDepot) {
        if ($line -match "{") { $depth++ }
        if ($line -match "}") {
            $depth--
            if ($depth -le 0) { $inDepot = $false; $inBranch = $false }
        }
        if (-not $inBranch -and $line -match "^\s*`"$Branch`"\s*$") {
            $inBranch = $true
            continue
        }
        if ($inBranch -and $line -match '"gid"') {
            $gid = ($line -replace '[^0-9]', '')
            break
        }
    }
}

if ([string]::IsNullOrEmpty($gid)) {
    Write-Error "Could not resolve manifest ID for depot $DepotId on branch $Branch"
    exit 1
}

Write-Host "Resolved depot $DepotId ($Codename) to manifest $gid on branch $Branch"

& $SteamCmd +login anonymous +download_depot $AppId $DepotId $gid +quit

if (-not (Test-Path $DownloadDir)) {
    Write-Error "Depot download did not produce expected folder: $DownloadDir"
    exit 1
}

Copy-Item -Path (Join-Path $DownloadDir '*') -Destination $BaseDir -Recurse -Force
Remove-Item -Path $DownloadDir -Recurse -Force
Remove-Item -Path $AppInfo -Force -ErrorAction SilentlyContinue

Write-Host "Installed Creator DLC '$Codename' (depot $DepotId) into $BaseDir"
