#!/bin/zsh
# device-turn.sh "<question>" <tag> · install the built app, launch it with NB_DEBUG_TURN, grab the screen twice.
SCR=${NB_DEV_DIR:-$(dirname $0)}
GRAB=${NB_SCREENGRAB:-/private/tmp/claude-501/-Users-zihuangwu-Documents-Next/274ad21d-a07f-4df4-9754-15068564bfe7/scratchpad/ScreenGrab.app}
UDID=00008150-0011293C2E21401C; CD=8D5E60E3-E60A-5A23-8EBF-0FCFE6661E36
Q="$1"; TAG="$2"
pkill -f idevicesyslog 2>/dev/null; sleep 1
idevicesyslog -u $UDID --no-colors -o $SCR/$TAG.syslog.txt &
SYS=$!
xcrun devicectl device install app --device $CD $SCR/dd/Build/Products/Debug-iphoneos/NextBody.app 2>&1 | tail -2
xcrun devicectl device process launch --terminate-existing -e "{\"NB_DEBUG_TURN\":\"$Q\"}" --device $CD com.nextbody.hoop 2>&1 | tail -2
sleep 30
open -W -a $GRAB --args $SCR/$TAG-a.png zihuang
sleep 14
open -W -a $GRAB --args $SCR/$TAG-b.png zihuang
kill $SYS 2>/dev/null
echo "--- syslog · turn lines ---"
grep "NextBody(" $SCR/$TAG.syslog.txt | grep -i "NB turn\|NB asr\|debug\|turn" | tail -12
ls -la $SCR/$TAG-a.png $SCR/$TAG-b.png 2>&1
