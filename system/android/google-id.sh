#!/bin/bash
# Google Play on Waydroid needs the device registered: prints the Android id to enter at
# https://www.google.com/android/uncertified (run after the first start of Google Play).
source "$(dirname "$(readlink -f "$0")")/../common.sh"
waydroid shell -- sh -c 'sqlite3 /data/data/com.google.android.gsf/databases/gservices.db "select value from main where name=\"android_id\";"'
