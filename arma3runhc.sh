#!/bin/bash

# Arguments: <number_clients> <server_binding> <server_port> "<server_password>" "<mod_list>"

netcommand="$(command -v "ss" 2>&1 >/dev/null && echo "ss" || echo "netstat")"

# Check if no headless clients are to be run
# If none, immediately exit
[[ $1 -eq 0 ]] && exit 0

# Start the headless clients
baseport=$(($3 + 498))
export LD_LIBRARY_PATH=`dirname $0`/linux64:$LD_LIBRARY_PATH
cd ./arma3/233780
for i in $(seq 1 $1); do
  if [[ "$2" == "0.0.0.0" ]]; then
    connect="127.0.0.1"
  else
    connect="$2"
  fi
  ./arma3server_x64 -client -nosound -connect="$connect:$3" -port="$baseport" -password="$4" "-mod=$5" 2>&1 >/dev/null &
  clients+=($!)
done

# Check if server starts successfully within 3 minutes
# If not, terminate headless clients
server_started=false
for i in $(seq 1 180); do
  if $netcommand -uln | grep -q ":$3 "; then
    server_started=true
    break
  fi
  sleep 1
done

if ! $server_started; then
  for client in "${clients[@]}"; do
    kill $client 2>&1 >/dev/null
  done
  exit 1
fi

# Monitor server process and terminate headless clients
# when server terminates
trap 'kill "${clients[@]}" 2>&1 >/dev/null' SIGTERM
while true; do
  if ! $netcommand -uln | grep -q ":$3 "; then
    for client in "${clients[@]}"; do
      kill $client 2>&1 >/dev/null
    done
    exit 0
  fi
  sleep 1
done
