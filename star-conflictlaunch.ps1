# Star Conflict server launcher for AMP (Windows).
# Starts the bundled MongoDB, then Hub (which starts the other server services),
# copies Hub's log to the console, and shuts both down cleanly on "quit".
param(
    [Parameter(Mandatory = $true)][string]$ServerDir,
    [Parameter(Mandatory = $true)][string]$DataDir,
    [int]$HubPort = 3850,
    [int]$HubStatusPort = 9001,
    [int]$MongoPort = 27017,
    [int]$LoadBalancerPort = 3801,
    [int]$ShardPort = 3802,
    [int]$ChatPort = 3815,
    [int]$BattlePort = 35000,
    [string]$PublicAddress = '',
    [string]$DetectedIP = ''
)

$ErrorActionPreference = 'Stop'
$ServerDir = [IO.Path]::GetFullPath($ServerDir).TrimEnd('\')
$DataDir = [IO.Path]::GetFullPath($DataDir).TrimEnd('\')
$CloudDir = Join-Path $ServerDir 'cloud'
$CfgDir = Join-Path $CloudDir 'data'
$MongoDir = Join-Path $CloudDir 'mongodb'
$DbDir = Join-Path $DataDir 'database'
$LogDir = Join-Path $DataDir 'logs'

function Say([string]$Text) { [Console]::Out.WriteLine($Text); [Console]::Out.Flush() }

function Get-ServerProcesses {
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($CloudDir + '\', [StringComparison]::OrdinalIgnoreCase) } catch { $false }
    }
}

function Test-Port([int]$Port) {
    $c = New-Object Net.Sockets.TcpClient
    try { $c.Connect('127.0.0.1', $Port); return $true } catch { return $false } finally { $c.Close() }
}

function Write-Cfg([string]$Name, [string[]]$Lines) {
    $text = "// Written by AMP on every start. Put your own settings in the matching .cfg file.`r`n" + ($Lines -join "`r`n") + "`r`n"
    [IO.File]::WriteAllText((Join-Path $CfgDir $Name), $text, (New-Object Text.UTF8Encoding $false))
}

if (-not (Test-Path (Join-Path $CloudDir 'Hub.exe'))) {
    Say "ERROR: $CloudDir\Hub.exe was not found. Run Update first."
    exit 1
}

# Processes left over from a run that didn't stop cleanly would hold the ports.
$stale = @(Get-ServerProcesses)
if ($stale.Count -gt 0) {
    Say "Stopping $($stale.Count) server process(es) left over from a previous run."
    $stale | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

New-Item -ItemType Directory -Force -Path $DbDir, $LogDir | Out-Null

# Address the services hand out to game clients.
$advertised = $PublicAddress.Trim()
if (-not $advertised -and $DetectedIP -match '^\d{1,3}(\.\d{1,3}){3}$' -and $DetectedIP -notmatch '^(0\.|127\.)') { $advertised = $DetectedIP }
if ($advertised) { Say "Players will be sent to $advertised." }
else { Say "WARNING: No Public Address is set and the external IP is unknown; only clients on this machine can connect." }

$override = @()
if ($advertised) { $override = @("set net_overrideShardAddr `"$advertised`"", "set net_overrideChatServerAddr `"$advertised`"") }
# Fixed database names: by default the game adds the user and machine name to
# them, so a moved instance or a different service account would get empty ones.
Write-Cfg 'common_local.cfg' @("set db_mongoHosts `"127.0.0.1:$MongoPort`"", 'set db_name "cosmosim_amp"', 'set db_stats_name "stats_cosmosim_amp"', 'set db_dedicatedDbCollectionSuffix "_amp"')
Write-Cfg 'hub_local.cfg' @("set hub_listenTo `"$HubPort`"", "set jsonp_listenPort $HubStatusPort")
Write-Cfg 'loadbalancer_local.cfg' (@("set lb_listenTo `"$LoadBalancerPort`"") + $override)
$dsOverride = @(); if ($advertised) { $dsOverride = @("set net_overrideDedicatedServerAddr `"$advertised`"") }
Write-Cfg 'shard_local.cfg' (@("set shard_listenTo `"$ShardPort`"") + $dsOverride)
Write-Cfg 'chat_server_local.cfg' @("set chat_server_port `"$ChatPort`"")
Write-Cfg 'dediserver_local.cfg' @("set net_gamePort `"$BattlePort`"")

# Hub only starts when the node address in cloud.xml is one of this machine's
# addresses and uses its own port, so keep it on loopback with the Hub port.
$cloudXml = Join-Path $CfgDir 'cloud.xml'
$xml = [IO.File]::ReadAllText($cloudXml)
$newXml = [regex]::Replace($xml, '(<Node\s[^>]*address=")[^"]*(")', "`${1}127.0.0.1:$HubPort`${2}")
if ($newXml -ne $xml) { [IO.File]::WriteAllText($cloudXml, $newXml, (New-Object Text.UTF8Encoding $false)) }

Say "Starting MongoDB on 127.0.0.1:$MongoPort ..."
$mongoArgs = "--bind_ip 127.0.0.1 --port $MongoPort --dbpath `"$DbDir`" --logpath `"$LogDir\mongod.log`" --logappend"
$mongo = Start-Process -FilePath (Join-Path $MongoDir 'mongod.exe') -ArgumentList $mongoArgs -WorkingDirectory $MongoDir -WindowStyle Hidden -PassThru
$deadline = (Get-Date).AddSeconds(90)
while (-not (Test-Port $MongoPort)) {
    if ($mongo.HasExited -or (Get-Date) -gt $deadline) {
        Say "ERROR: MongoDB did not start. Last lines of logs\mongod.log:"
        if (Test-Path "$LogDir\mongod.log") { Get-Content "$LogDir\mongod.log" -Tail 15 | ForEach-Object { Say $_ } }
        if (-not $mongo.HasExited) { $mongo | Stop-Process -Force }
        exit 1
    }
    Start-Sleep -Milliseconds 500
}
Say "MongoDB is up."

function Stop-Mongo {
    if ($mongo.HasExited) { return }
    Say "Stopping MongoDB ..."
    & (Join-Path $MongoDir 'mongo.exe') --quiet --port $MongoPort admin --eval "db.shutdownServer()" *> $null
    if (-not $mongo.WaitForExit(30000)) { $mongo | Stop-Process -Force -ErrorAction SilentlyContinue }
    Say "MongoDB stopped."
}

$started = Get-Date
# Hub appends to one log file per day; only show what this run writes.
$logStart = @{}
Get-ChildItem -Path (Join-Path $LogDir 'hub_*.log') -ErrorAction SilentlyContinue | ForEach-Object { $logStart[$_.FullName] = $_.Length }
Say "Starting Hub on port $HubPort ..."
$hub = Start-Process -FilePath (Join-Path $CloudDir 'Hub.exe') -ArgumentList "-outputDir `"$DataDir`"" -WorkingDirectory $CloudDir -WindowStyle Hidden -PassThru

function Stop-Hub {
    if (-not $hub.HasExited) {
        Say "Stopping Hub and the server services ..."
        # The services save to MongoDB as they go and exit on their own once Hub is gone.
        $hub | Stop-Process -Force -ErrorAction SilentlyContinue
        $hub.WaitForExit(15000) | Out-Null
    }
    $deadline = (Get-Date).AddSeconds(30)
    while (@(Get-ServerProcesses | Where-Object { $_.Id -ne $mongo.Id }).Count -gt 0 -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    Get-ServerProcesses | Where-Object { $_.Id -ne $mongo.Id } | Stop-Process -Force -ErrorAction SilentlyContinue
    Say "Hub stopped."
}

# Copy Hub's log to the console and watch for "quit" on stdin.
$logFile = $null; $stream = $null; $reader = $null
# Console.In blocks even in ReadLineAsync, so read the raw stdin stream.
$stdin = New-Object IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)
$pending = $stdin.ReadLineAsync()
$exitCode = 0
$announced = $false
$nextProbe = Get-Date
try {
    while ($true) {
        $newest = Get-ChildItem -Path (Join-Path $LogDir 'hub_*.log') -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $started.AddSeconds(-5) } | Sort-Object LastWriteTime | Select-Object -Last 1
        if ($newest -and $newest.FullName -ne $logFile) {
            if ($reader) { $reader.Dispose() }
            $logFile = $newest.FullName
            $stream = New-Object IO.FileStream($logFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
            if ($logStart.ContainsKey($logFile)) { [void]$stream.Seek([long]$logStart[$logFile], [IO.SeekOrigin]::Begin) }
            $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
        }
        if ($reader) {
            while ($null -ne ($line = $reader.ReadLine())) { Say $line }
        }

        # Hub registers the services before the shard has loaded its data, so check the player ports.
        if (-not $announced -and (Get-Date) -ge $nextProbe) {
            $nextProbe = (Get-Date).AddSeconds(2)
            if ((Test-Port $LoadBalancerPort) -and (Test-Port $ShardPort) -and (Test-Port $ChatPort)) {
                Say "Star Conflict server is ready: load balancer, shard and chat ports are listening."
                $announced = $true
            }
        }

        if ($pending.IsCompleted) {
            $cmd = $pending.Result
            if ($null -eq $cmd -or $cmd.Trim() -match '^/?(quit|stop|exit)$') { break }
            if ($cmd.Trim()) { Say "Only 'quit' is supported here. Use Hub's remote console for server commands." }
            $pending = $stdin.ReadLineAsync()
        }

        if ($hub.HasExited) {
            Say "Hub exited unexpectedly (exit code $($hub.ExitCode)). Its logs are in the logs folder."
            $exitCode = 1
            break
        }
        Start-Sleep -Milliseconds 250
    }
}
finally {
    Stop-Hub
    if ($reader) { while ($null -ne ($line = $reader.ReadLine())) { Say $line }; $reader.Dispose() }
    Stop-Mongo
}
exit $exitCode
