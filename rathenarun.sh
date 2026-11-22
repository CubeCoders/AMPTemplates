#!/bin/bash
# Runs the bundled MariaDB server and the rAthena login, char, map (and optionally web) servers as one process for AMP.
# Settings arrive as environment variables set by the AMP template.

BASEDIR=$(dirname "$(readlink -f "$0")")
SERVERDIR="$BASEDIR/server"
DATADIR="$BASEDIR/mysql"
RUNDIR="$BASEDIR/run"
SOCKET="$RUNDIR/mariadbd.sock"
DB_PORT="${RA_DB_PORT:-3306}"
DB_NAME="ragnarok"
DB_USER="ragnarok"
PIDS=()
WATCH_PID=""
DB_PID=""
CONSOLE_FIFO="$RUNDIR/map-console.fifo"

sql_escape() { local s="${1//\\/\\\\}"; printf '%s' "${s//\'/\'\'}"; }
db() { mariadb --no-defaults --protocol=socket --socket="$SOCKET" "$@"; }

stop_all() {
  trap - TERM INT
  [[ -n "$WATCH_PID" ]] && kill "$WATCH_PID" 2>/dev/null
  echo "Stopping rAthena servers..."
  for (( i=${#PIDS[@]}-1; i>=0; i-- )); do
    kill -TERM "${PIDS[$i]}" 2>/dev/null
    wait "${PIDS[$i]}" 2>/dev/null
  done
  if [[ -n "$DB_PID" ]]; then
    echo "Stopping MariaDB server..."
    mariadb-admin --no-defaults --protocol=socket --socket="$SOCKET" shutdown >/dev/null 2>&1 || kill -TERM "$DB_PID" 2>/dev/null
    wait "$DB_PID" 2>/dev/null
  fi
  exec 3>&- 2>/dev/null
  rm -f "$CONSOLE_FIFO"
  echo "rAthena stopped"
  exit "${1:-0}"
}
trap 'stop_all 0' TERM INT

for s in login-server char-server map-server; do
  [[ -x "$SERVERDIR/$s" ]] || { echo "$s was not found. Run Update to download and build rAthena"; exit 1; }
done
command -v mariadbd >/dev/null 2>&1 || { echo "MariaDB is not installed. This template needs to run in a container"; exit 1; }

mkdir -p "$RUNDIR" "$SERVERDIR/log"

# Initialise the database directory on first start
if [[ ! -d "$DATADIR/mysql" ]]; then
  echo "Creating MariaDB data directory..."
  mariadb-install-db --no-defaults --datadir="$DATADIR" --auth-root-authentication-method=socket >/dev/null || { echo "MariaDB initialisation failed"; exit 1; }
fi

# Start MariaDB, reachable only from inside the instance
mariadbd --no-defaults --datadir="$DATADIR" --socket="$SOCKET" --pid-file="$RUNDIR/mariadbd.pid" \
  --port="$DB_PORT" --bind-address=127.0.0.1 --skip-name-resolve --log-error="$BASEDIR/mysql-error.log" &
DB_PID=$!
for (( t=0; t<60; t++ )); do
  mariadb-admin --no-defaults --protocol=socket --socket="$SOCKET" ping >/dev/null 2>&1 && break
  kill -0 "$DB_PID" 2>/dev/null || { echo "MariaDB failed to start. See mysql-error.log"; DB_PID=""; exit 1; }
  sleep 1
done
(( t >= 60 )) && { echo "MariaDB did not respond within 60 seconds"; stop_all 1; }
echo "MariaDB server is running"

# Create the rAthena database on first start, then keep its credentials in line with the AMP settings
DB_PASS=$(sql_escape "$RA_DB_PASS")
IS_USER=$(sql_escape "$RA_IS_USER")
IS_PASS=$(sql_escape "$RA_IS_PASS")
if ! db -e "USE \`$DB_NAME\`" >/dev/null 2>&1; then
  echo "Creating database '$DB_NAME' and importing rAthena tables..."
  db -e "CREATE DATABASE \`$DB_NAME\`" || stop_all 1
  for f in main.sql logs.sql web.sql roulette_default_data.sql; do
    [[ -f "$SERVERDIR/sql-files/$f" ]] || continue
    db "$DB_NAME" < "$SERVERDIR/sql-files/$f" || { echo "Importing $f failed"; db -e "DROP DATABASE \`$DB_NAME\`"; stop_all 1; }
  done
  echo "Database created. Apply files from sql-files/upgrades yourself after rAthena updates that change the schema"
fi
db -e "CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS'; ALTER USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS'; CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS'; ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS'; GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1'; GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" || stop_all 1
[[ -n "$RA_IS_USER" && -n "$RA_IS_PASS" ]] && db "$DB_NAME" -e "UPDATE \`login\` SET \`userid\`='$IS_USER', \`user_pass\`='$IS_PASS' WHERE \`account_id\`=1 AND \`sex\`='S';"

# Start the rAthena servers. Console input goes to the map-server
cd "$SERVERDIR" || stop_all 1
rm -f "$CONSOLE_FIFO"; mkfifo "$CONSOLE_FIFO"; exec 3<>"$CONSOLE_FIFO"
SERVERS=(login-server char-server map-server)
[[ "${RA_WEB,,}" == "true" && -x ./web-server ]] && SERVERS+=(web-server)
for s in "${SERVERS[@]}"; do
  if [[ "$s" == "map-server" ]]; then "./$s" <&3 & else "./$s" </dev/null & fi
  PIDS+=($!)
  sleep 2
done

# Stop everything if any server exits on its own
( while sleep 2; do for p in "${PIDS[@]}"; do kill -0 "$p" 2>/dev/null || { echo "A rAthena server process exited. Shutting down"; kill -TERM $$; exit 0; }; done; done ) &
WATCH_PID=$!

while read -r line; do
  case "${line,,}" in
    exit|stop|quit|shutdown) break ;;
    *) printf '%s\n' "$line" >&3 ;;
  esac
done
stop_all 0
