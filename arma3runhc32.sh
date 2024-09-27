#!/bin/bash

# Arguments: [number_clients] [server_binding] [server_port] "<server_password>" "<mod_list>" "<hc_parameters_file>" [start_limit]

netcommand="$(command -v "ss" >/dev/null 2>&1 && echo "ss" || echo "netstat")"

# Check if any headless clients are to be run
# If none, immediately exit
[[ $1 -eq 0 ]] && exit 0

# Check if server starts successfully within <start_limit> seconds
# If not, exit
server_started=false
startlimit=${7:-180}
for i in $(seq 1 $startlimit); do
  if $netcommand -uln | grep -q ":$3 "; then
    server_started=true
    break
  fi
  sleep 1
done
if ! $server_started; then
  exit 0
fi

# Start the headless clients
baseport=$(($3 + 498))
parfile="${6:-}"
export LD_LIBRARY_PATH=$(dirname "$0")/arma3/linux32:$LD_LIBRARY_PATH
cd ./arma3/233780
for i in $(seq 1 "$1"); do
  if [[ "$2" == "0.0.0.0" ]]; then
    connect="127.0.0.1"
  else
    connect="$2"
  fi
  ./arma3server -client -nosound -profiles=A3Master -connect=$connect:$3 -port=$baseport -password="$4" "-mod=$5" "-par=$parfile" >/dev/null 2>&1 &
  clients+=($!)
done

# Monitor server process and terminate headless clients
# when server terminates or SIGTERM/SIGINT received
trap 'for client in "${clients[@]}"; do kill "$client" >/dev/null 2>&1; done; wait' SIGTERM SIGINT
while true; do
  if ! $netcommand -uln | grep -q ":$3 "; then
    for client in "${clients[@]}"; do
      kill "$client" >/dev/null 2>&1
    done
    wait
    exit 0
  fi
  sleep 1
done
