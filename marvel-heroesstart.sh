#!/bin/bash
# MHServerEmu stays blocked reading the console after "!server shutdown", so send one more line once it has shut down.
cd "$(dirname "$0")/MHServerEmu" || exit 1
exec ./MHServerEmu < <(while IFS= read -r line; do
    printf '%s\n' "$line"
    if [ "${line%$'\r'}" = '!server shutdown' ]; then sleep 2; echo; exit; fi
done)
