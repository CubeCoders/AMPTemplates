# Notes

## General information

PZ wiki:
https://pzwiki.net/wiki/Main_Page

Dedicated server wiki:
https://pzwiki.net/wiki/Dedicated_Server

Server configuration file options:
https://steamsplay.com/project-zomboid-how-to-host-server-via-linux-tutorial/

Server command line paramters:
https://pzwiki.net/wiki/Startup_parameters

## To do items

Figure out how to add launch var on Linux, ie how to set `LD_PRELOAD` as is done by `start-server.sh`:

`JSIG="libjsig.so"
LD_PRELOAD="${LD_PRELOAD}:${JSIG}" ./ProjectZomboid64 "$@"`

The other envvars are set fine.
