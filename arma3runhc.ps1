# Arguments: [number_clients] [server_binding] [server_port] "<server_password>" "<mod_list>" "<-par=hc_parameters.txt>"

# Check if any headless clients are to be run
# If none, immediately exit
if ($args[0] -eq "0") { exit }

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
if (-not $serverStarted) { exit 1 }

# Start the headless clients
$clients = @()
$basePort = [int]$args[2] + 498
if ($args.Length -lt 6) { 
    $parfile_arg = ""
} else {
    $parfile_arg = $args[6]
}
cd "$PSScriptRoot\arma3\233780"
for ($i = 1; $i -le [int]$args[0]; $i++) {
  if ($args[1] -eq "0.0.0.0") {
    $connect = "127.0.0.1"
  } else {
    $connect = $args[1]
  }
  $hcProcess = Start-Process -FilePath "ArmA3Server_x64.exe" -ArgumentList "-client", "-nosound", "-profiles=A3Master", "-connect=${connect}:$($args[2])", "-port=$basePort", "-password=`"$($args[3])`"", "`"-mod=$($args[4])`"", "`"$parfile_arg`"" -WindowStyle Hidden -PassThru
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
