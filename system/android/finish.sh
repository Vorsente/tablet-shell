#!/bin/bash
# User part (no sudo): start the Android session and install F-Droid. Apps appear on the home screen.
set -e
waydroid session start >/dev/null 2>&1 &
for i in $(seq 1 90); do
    waydroid status 2>/dev/null | grep -q 'Session:.*RUNNING' && break
    sleep 2
done
waydroid status
# Android apps in their own windows crash surfaceflinger on current images: keep the single window
waydroid prop set persist.waydroid.multi_windows false
waydroid prop set persist.waydroid.width_padding 0 || true
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/F-Droid.apk" https://f-droid.org/F-Droid.apk
waydroid app install "$tmp/F-Droid.apk"
rm -rf "$tmp"
echo "Android: OK"
