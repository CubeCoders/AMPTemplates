#!/bin/bash

# Arma 3 headless clients script
# Run with ./arma3_headless_clients.sh <number_clients> <server_binding> <server_port> <server_password> <mod_list> &
# In AMP pre-start stage: ./arma3_headless_clients.sh {{HeadlessClients}} {{$ApplicationIPBinding}} {{$GamePort}} {{password}} {{mod}}

# Function to check if a port is available
function port_available() {
  local port=$1
  if [[ $(netstat -tln | grep ":$port " | wc -l) -eq 0 ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

# Start the headless clients
for i in $(seq 1 $1); do
  port=$((3300+i))
  while [ $(port_available $port) == "no" ]; do
    port=$((port+1))
  done
  if [[ "$2" == "0.0.0.0" ]]; then
    connect="127.0.0.1"
  else
    connect="$2"
  fi
  ./arma3server -client -nosound -connect="$connect:$3" -port="$port" -password="$4" "-mod=$5" 2>&1 >/dev/null &
  clients+=($!)
done

# Check if server starts successfully within 2 minutes
# If not, terminate headless clients
server_started=false
for i in $(seq 1 120); do
  if netstat -ln | grep -q ":$3 "; then
    server_started=true
    break
  fi
  sleep 1
done

if ! $server_started; then
  for client in "${clients[@]}"; do
    kill $client >/dev/null 2>&1
  done
  exit 1
fi

# Monitor server process and terminate headless clients
# when server terminates
trap 'kill "${clients[@]}" >/dev/null 2>&1' SIGTERM
while true; do
  if ! netstat -ln | grep -q ":$3 "; then
    for client in "${clients[@]}"; do
      kill $client >/dev/null 2>&1
    done
    exit 0
  fi
  sleep 1
done
