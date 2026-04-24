#!/bin/bash

# Arguments: [http_port] (bind_ip)

scriptDir=$(pwd)
serverProcess="Z:${scriptDir//\//\\}\\windrose\\4129620\\R5\\Binaries\\Win64\\WindroseServer-Win64-Shipping.exe"
export TEMP=${TMPDIR:-/tmp}

# Check if Windrose server starts successfully within 1 minute
# If not, exit
serverStarted=false
for i in $(seq 1 60); do
    serverPid=$(ps aux | grep -F "${serverProcess}" | grep -v grep | awk '{print $2}')
    if [[ -n "$serverPid" ]]; then
        serverStarted=true
        break
    fi
    sleep 1
done
if ! $serverStarted; then
    exit 0
fi

# Start the Windrose+ dashboard
cd ./windrose/4129620
powershell/pwsh -NoProfile -File "$scriptDir/windrose/4129620/windrose_plus/server/windrose_plus_server.ps1" -Port $1 ${2:+-BindIp "$2"} -GameDir "$scriptDir/windrose/4129620" &
dashboardPid=$!

# Exit if dashboard fails to start
sleep 10
if ! kill -0 "$dashboardPid" 2>/dev/null; then
    exit 0
fi

# Monitor server process and terminate dashboard
# when server terminates or SIGTERM/SIGINT received
trap 'kill $dashboardPid' SIGTERM SIGINT
while true; do
    if ! kill -0 "$serverPid" 2>/dev/null; then
        kill "$dashboardPid" >/dev/null 2>&1
        exit 0
    fi
    sleep 1
done
