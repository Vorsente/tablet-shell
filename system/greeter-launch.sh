#!/bin/sh
# Start the greeter silently: cage/libseat/Qt output must not leak onto the login VT.
# No session logs are created. Do not silence greetd itself or other system services.
exec </dev/null >/dev/null 2>&1
export LANG="${LANG:-en_US.UTF-8}"
export LIBSEAT_BACKEND=logind
export LIBSEAT_LOGLEVEL=silent
export WLR_LOG=silent
export XDG_SESSION_TYPE=wayland
# Qt shader caches are not diagnostic logs.
export QML_DISK_CACHE_PATH=/var/cache/tablet-greeter
exec /usr/bin/cage -s -m last -- /usr/local/bin/tablet-greeter
