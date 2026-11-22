#!/bin/bash
# Star Conflict server launcher for AMP (Linux, Wine).
# Starts the bundled MongoDB, then Hub (which starts the other server services),
# copies Hub's log to the console, and shuts both down cleanly on "quit".
# Usage: star-conflictlaunch.sh <ServerDir> <DataDir> <HubPort> <HubStatusPort> <MongoPort>
#        <LoadBalancerPort> <ShardPort> <ChatPort> <BattlePort> [PublicAddress] [ExternalIP]

SERVER_DIR="${1%/}"
DATA_DIR="${2%/}"
HUB_PORT="${3:-3850}"
HUB_STATUS_PORT="${4:-9001}"
MONGO_PORT="${5:-27017}"
LB_PORT="${6:-3801}"
SHARD_PORT="${7:-3802}"
CHAT_PORT="${8:-3815}"
BATTLE_PORT="${9:-35000}"
PUBLIC_ADDRESS="$(printf '%s' "${10}" | tr -d '[:space:]')"
EXTERNAL_IP="${11}"

CLOUD_DIR="$SERVER_DIR/cloud"
CFG_DIR="$CLOUD_DIR/data"
MONGO_DIR="$CLOUD_DIR/mongodb"
DB_DIR="$DATA_DIR/database"
LOG_DIR="$DATA_DIR/logs"
WINE=/usr/bin/wine

say() { printf '%s\n' "$*"; }

if [ ! -f "$CLOUD_DIR/Hub.exe" ]; then
    say "ERROR: $CLOUD_DIR/Hub.exe was not found. Run Update first."
    exit 1
fi
if [ ! -x "$WINE" ]; then
    say "ERROR: Wine was not found at $WINE."
    exit 1
fi

# Wine processes left over from a run that didn't stop cleanly would hold the ports.
wineserver -k >/dev/null 2>&1
sleep 1

mkdir -p "$DB_DIR" "$LOG_DIR"
WIN_DB_DIR="$(winepath -w "$DB_DIR" 2>/dev/null)"
WIN_LOG_DIR="$(winepath -w "$LOG_DIR" 2>/dev/null)"
WIN_DATA_DIR="$(winepath -w "$DATA_DIR" 2>/dev/null)"

# Address the services hand out to game clients.
ADVERTISED="$PUBLIC_ADDRESS"
if [ -z "$ADVERTISED" ] && [[ "$EXTERNAL_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && [[ ! "$EXTERNAL_IP" =~ ^(0\.|127\.) ]]; then
    ADVERTISED="$EXTERNAL_IP"
fi
if [ -n "$ADVERTISED" ]; then
    say "Players will be sent to $ADVERTISED."
else
    say "WARNING: No Public Address is set and the external IP is unknown; only clients on this machine can connect."
fi

write_cfg() {
    local name="$1"; shift
    {
        printf '// Written by AMP on every start. Put your own settings in the matching .cfg file.\r\n'
        for l in "$@"; do printf '%s\r\n' "$l"; done
    } > "$CFG_DIR/$name"
}

LB_LINES=("set lb_listenTo \"$LB_PORT\"")
SHARD_LINES=("set shard_listenTo \"$SHARD_PORT\"")
if [ -n "$ADVERTISED" ]; then
    LB_LINES+=("set net_overrideShardAddr \"$ADVERTISED\"" "set net_overrideChatServerAddr \"$ADVERTISED\"")
    SHARD_LINES+=("set net_overrideDedicatedServerAddr \"$ADVERTISED\"")
fi
write_cfg common_local.cfg "set db_mongoHosts \"127.0.0.1:$MONGO_PORT\""
write_cfg hub_local.cfg "set hub_listenTo \"$HUB_PORT\"" "set jsonp_listenPort $HUB_STATUS_PORT"
write_cfg loadbalancer_local.cfg "${LB_LINES[@]}"
write_cfg shard_local.cfg "${SHARD_LINES[@]}"
write_cfg chat_server_local.cfg "set chat_server_port \"$CHAT_PORT\""
write_cfg dediserver_local.cfg "set net_gamePort \"$BATTLE_PORT\""

# Hub only starts when the node address in cloud.xml is one of this machine's
# addresses and uses its own port, so keep it on loopback with the Hub port.
sed -i -E "s#(<Node[[:space:]][^>]*address=\")[^\"]*(\")#\\1127.0.0.1:$HUB_PORT\\2#" "$CFG_DIR/cloud.xml"

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1; }

say "Starting MongoDB on 127.0.0.1:$MONGO_PORT ..."
cd "$MONGO_DIR" || exit 1
"$WINE" ./mongod.exe --bind_ip 127.0.0.1 --port "$MONGO_PORT" --dbpath "$WIN_DB_DIR" --logpath "$WIN_LOG_DIR\\mongod.log" --logappend </dev/null >/dev/null 2>&1 &
MONGO_PID=$!
for _ in $(seq 1 180); do
    port_open "$MONGO_PORT" && break
    if ! kill -0 "$MONGO_PID" 2>/dev/null; then break; fi
    sleep 0.5
done
if ! port_open "$MONGO_PORT"; then
    say "ERROR: MongoDB did not start. Last lines of logs/mongod.log:"
    tail -n 15 "$LOG_DIR/mongod.log" 2>/dev/null
    wineserver -k >/dev/null 2>&1
    exit 1
fi
say "MongoDB is up."

stop_mongo() {
    kill -0 "$MONGO_PID" 2>/dev/null || return
    say "Stopping MongoDB ..."
    (cd "$MONGO_DIR" && timeout 30 "$WINE" ./mongo.exe --quiet --port "$MONGO_PORT" admin --eval "db.shutdownServer()" </dev/null >/dev/null 2>&1)
    for _ in $(seq 1 60); do kill -0 "$MONGO_PID" 2>/dev/null || break; sleep 0.5; done
    kill -0 "$MONGO_PID" 2>/dev/null && kill -9 "$MONGO_PID" 2>/dev/null
    say "MongoDB stopped."
}

STARTED=$(date +%s)
# Hub appends to one log file per day; only show what this run writes.
declare -A LOG_START
for f in "$LOG_DIR"/hub_*.log; do [ -f "$f" ] && LOG_START["$f"]=$(stat -c %s "$f"); done
say "Starting Hub on port $HUB_PORT ..."
cd "$CLOUD_DIR" || exit 1
"$WINE" ./Hub.exe -outputDir "$WIN_DATA_DIR" </dev/null >/dev/null 2>&1 &
HUB_PID=$!

stop_hub() {
    if kill -0 "$HUB_PID" 2>/dev/null; then
        say "Stopping Hub and the server services ..."
        # Wine passes SIGINT to Hub as Ctrl+C, which shuts its services down cleanly.
        kill -INT "$HUB_PID" 2>/dev/null
        for _ in $(seq 1 120); do kill -0 "$HUB_PID" 2>/dev/null || break; sleep 0.5; done
        kill -0 "$HUB_PID" 2>/dev/null && kill -9 "$HUB_PID" 2>/dev/null
    fi
    # Give the services a moment to exit; anything left is ended with the Wine prefix.
    sleep 5
    say "Hub stopped."
}

LOG_FILE=""
TAIL_PID=""
EXIT_CODE=0
cleanup() {
    stop_hub
    sleep 1
    [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null
    stop_mongo
    wineserver -k >/dev/null 2>&1
}
trap 'cleanup; exit 0' TERM INT

while true; do
    NEWEST="$(find "$LOG_DIR" -maxdepth 1 -name 'hub_*.log' -newermt "@$((STARTED - 5))" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-)"
    if [ -n "$NEWEST" ] && [ "$NEWEST" != "$LOG_FILE" ]; then
        [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null
        LOG_FILE="$NEWEST"
        tail -c +$(( ${LOG_START["$LOG_FILE"]:-0} + 1 )) -F "$LOG_FILE" 2>/dev/null > >(sed -u 's/\r$//') &
        TAIL_PID=$!
    fi

    # Hub registers the services before the shard has loaded its data, so check the player ports.
    if [ -z "$ANNOUNCED" ] && port_open "$LB_PORT" && port_open "$SHARD_PORT" && port_open "$CHAT_PORT"; then
        say "Star Conflict server is ready: load balancer, shard and chat ports are listening."
        ANNOUNCED=1
    fi

    if read -r -t 1 CMD; then
        CMD="$(printf '%s' "$CMD" | tr -d '\r' | xargs)"
        if [[ "$CMD" =~ ^/?(quit|stop|exit)$ ]]; then break; fi
        [ -n "$CMD" ] && say "Only 'quit' is supported here. Use Hub's remote console for server commands."
    elif [ $? -le 128 ]; then
        break  # stdin closed
    fi

    if ! kill -0 "$HUB_PID" 2>/dev/null; then
        say "Hub exited unexpectedly. Its logs are in the logs folder."
        EXIT_CODE=1
        break
    fi
done

cleanup
exit $EXIT_CODE
