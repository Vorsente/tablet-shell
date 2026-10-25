#!/bin/sh
# Start the desktop session quietly. greetd gives the session the login VT as stdout/stderr, so
# messages of startplasma, KWin and libseat/seatd flashed on screen while Plasma started and at
# logout/shutdown. The session's own services still log to the journal as usual.
exec </dev/null >/dev/null 2>&1
export LIBSEAT_LOGLEVEL=silent
exec "$@"
