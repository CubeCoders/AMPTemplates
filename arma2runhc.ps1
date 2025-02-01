# Arguments: [number_clients] [server_binding] [server_port] "<server_password>" "<mod_list>" "<hc_parameters_file>"

# Check if any headless clients are to be run
# If none, immediately exit
if ($args[0] -eq "0") { exit 0 }

# Check if server starts successfully within 3 minutes
# If not, exit
$serverStarted = $false
for ($i = 1; $i -le 180; $i++) {
  if (Get-NetUDPEndpoint -LocalPort $args[2] -ErrorAction SilentlyContinue) {
    $serverStarted = $true
    break
  }
  Start-Sleep -Seconds 1
}
if (-not $serverStarted) { exit 0 }

# Start the headless clients
$clients = @()
$basePort = [int]$args[2] + 498
if ($args.Length -lt 6) { 
    $parfile = ""
} else {
    $parfile = $args[6]
}
cd "$PSScriptRoot\arma2\33905"
for ($i = 1; $i -le [int]$args[0]; $i++) {
  if ($args[1] -eq "0.0.0.0") {
    $connect = "127.0.0.1"
  } else {
    $connect = $args[1]
  }
  $hcProcess = Start-Process -FilePath "ArmA2.exe" -ArgumentList "0 0", "-client", "-nosplash", "-nosound", "-profiles=A2Master", "-connect=${connect}", "-port=$($args[2])", "-password=`"$($args[3])`"", "`"-mod=$($args[4])`"", "`"-par=$parfile`"" -WindowStyle Hidden -PassThru
  $clients += $hcProcess.Id
}

# Monitor server process and terminate headless clients
# when server terminates
while ($true) {
  if (-not (Get-NetUDPEndpoint -LocalPort $args[2] -ErrorAction SilentlyContinue)) {
    foreach ($processId in $clients) {
      Stop-Process -Id $processId -Force
    }
    exit 0
  }
  Start-Sleep -Seconds 1
}
