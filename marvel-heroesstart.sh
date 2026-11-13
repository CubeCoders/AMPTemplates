#!/bin/bash
# Args: web server on/off, HTTP port, HTTPS port, web frontend port, web frontend address, public address.
WEB=$1 HTTP=$2 HTTPS=$3 WEBPORT=$4 WEBADDR=$5 PUB=$6
ROOT=$(cd "$(dirname "$0")" && pwd)

# Optional Caddy web server: SiteConfig.xml over HTTP and an HTTPS proxy to the web frontend, as the client needs.
if [ "$WEB" = true ]; then
    D="$ROOT/caddy"
    mkdir -p "$D/www"
    # Port-patched clients use AuthServerPort; stock clients always use 443.
    sed -e "s|name=\"AuthServerAddress\" value=\"[^\"]*\"|name=\"AuthServerAddress\" value=\"$PUB\"|"         -e "s|name=\"AuthServerPort\" value=\"[^\"]*\"|name=\"AuthServerPort\" value=\"$HTTPS\"|" "$D/SiteConfig.template.xml" > "$D/www/SiteConfig.xml"
    cat > "$D/Caddyfile" <<EOF
{
	admin off
	persist_config off
	storage file_system "$D/data"
	http_port $HTTP
	https_port $HTTPS
	default_sni $PUB
	skip_install_trust
	auto_https disable_redirects
}
http://:$HTTP {
	root * "$D/www"
	file_server
}
https://$PUB:$HTTPS {
	tls internal
	reverse_proxy $WEBADDR:$WEBPORT {
		header_up Host $WEBADDR:$WEBPORT
	}
}
EOF
    "$D/caddy" run --config "$D/Caddyfile" --adapter caddyfile > "$D/caddy.log" 2>&1 &
    CADDY=$!
    sleep 2
    if kill -0 "$CADDY" 2>/dev/null; then
        echo "Built-in web server running: http://$PUB:$HTTP/SiteConfig.xml, https port $HTTPS"
    else
        echo "Built-in web server failed to start (ports $HTTP/$HTTPS in use or not permitted?). See caddy/caddy.log:"
        tail -n 3 "$D/caddy.log"
    fi
fi

# MHServerEmu stays blocked reading the console after "!server shutdown", so send one more line once it has shut down.
cd "$ROOT/MHServerEmu" || exit 1
./MHServerEmu < <(while IFS= read -r line; do
    printf '%s\n' "$line"
    if [ "${line%$'\r'}" = '!server shutdown' ]; then sleep 2; echo; exit; fi
done)
CODE=$?
[ -n "$CADDY" ] && kill "$CADDY" 2>/dev/null
exit $CODE
