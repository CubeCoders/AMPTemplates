# Arguments: [http_port]

$serverProcess = "$PSScriptRoot\windrose\4129620\R5\Binaries\Win64\WindroseServer-Win64-Shipping.exe"

# Check if Windrose server starts successfully within 1 minute
# If not, exit
$serverStarted = $false
for ($i = 1; $i -le 60; $i++) {
    if (Get-WmiObject Win32_Process | Where-Object {$_.ExecutablePath -eq "$serverProcess"} -ErrorAction SilentlyContinue) {
        $serverStarted = $true
        break
    }
    Start-Sleep -Seconds 1
}
if (-not $serverStarted) { exit 0 }

# Start the Windrose+ dashboard
$dashboardJob = Start-Job -ScriptBlock {
    param($scriptRoot, $port)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$scriptRoot\windrose\4129620\windrose_plus\server\windrose_plus_server.ps1" -Port $port -GameDir "$scriptRoot\windrose\4129620"
} -ArgumentList $PSScriptRoot, $args[0]

# Exit if dashboard fails to start
Start-Sleep -Seconds 10
Receive-Job -Id $dashboardJob.Id
if ((Get-Job -Id $dashboardJob.Id).State -ne 'Running') {
    Receive-Job -Id $dashboardJob.Id
    exit 0
}

# Monitor server process and terminate dashboard
# when server terminates
while ($true) {
    Receive-Job -Id $dashboardJob.Id
    if (-not (Get-WmiObject Win32_Process | Where-Object {$_.ExecutablePath -eq "$serverProcess"} -ErrorAction SilentlyContinue)) {
        Stop-Job -Id $dashboardJob.Id
        Receive-Job -Id $dashboardJob.Id
        Remove-Job -Id $dashboardJob.Id -Force
        exit 0
    }
    Start-Sleep -Seconds 1
}
