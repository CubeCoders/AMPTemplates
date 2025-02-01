#!/bin/bash

# Arguments: [number_clients] [server_binding] [server_port] "<server_password>" "<mod_list>" "<hc_parameters_file>"

netcommand="$(command -v "ss" >/dev/null 2>&1 && echo "ss" || echo "netstat")"

# Check if any headless clients are to be run
# If none, immediately exit
[[ $1 -eq 0 ]] && exit 0

# Check if server starts successfully within 3 minutes
# If not, exit
server_started=false
for i in $(seq 1 180); do
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
SCRIPT_NAME=$(echo \"$0\" | xargs readlink -f)
SCRIPTDIR=$(dirname "$SCRIPT_NAME")

exec 6>display.log
/usr/bin/Xvfb -displayfd 6 &
XVFB_PID=$!
while [[ ! -s display.log ]]; do
  sleep 1
done
read -r DPY_NUM < display.log
rm display.log

baseport=$(($3 + 498))
parfile="${6:-}"
export WINEPREFIX="$SCRIPTDIR/arma2/.wine"
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEARCH=win64
export WINEDEBUG=-all
export DISPLAY=:$DPY_NUM

cd ./arma2/33905
for i in $(seq 1 "$1"); do
  if [[ "$2" == "0.0.0.0" ]]; then
    connect="127.0.0.1"
  else
    connect="$2"
  fi
  /usr/bin/wine ArmA2.exe -client -nosplash -nosound -profiles=A2Master -connect=$connect -port=$3 -password="$4" "-mod=$5" &
  clients+=($!)
done

# Monitor server process and terminate headless clients
# when server terminates or SIGTERM/SIGINT received
trap 'for client in "${clients[@]}"; do kill "$client" >/dev/null 2>&1; done; wait "${clients[@]}"; exec 6>&-; kill $XVFB_PID' SIGTERM SIGINT
while true; do
  if ! $netcommand -uln | grep -q ":$3 "; then
    for client in "${clients[@]}"; do
      kill "$client" >/dev/null 2>&1
    done
    wait "${clients[@]}"
    exec 6>&-
    kill $XVFB_PID
    exit 0
  fi
  sleep 1
done

