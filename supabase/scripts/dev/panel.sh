#!/bin/zsh
# panel.sh <tag>… · pin one panel state per launch with NB_DEBUG_PANEL and grab it.
# Tags are a widget type (any of the 27) or the word `thinking`.
SCR=${NB_DEV_DIR:-$(dirname $0)}
GRAB=${NB_SCREENGRAB:?set NB_SCREENGRAB to ScreenGrab.app}
CD=${NB_DEVICE:-8D5E60E3-E60A-5A23-8EBF-0FCFE6661E36}
OUT=$SCR/panels; mkdir -p $OUT
xcrun devicectl device install app --device $CD $SCR/dd-lang/Build/Products/Debug-iphoneos/NextBody.app 2>&1 | tail -1
for tag in "$@"; do
  xcrun devicectl device process launch --terminate-existing \
    -e "{\"NB_DEBUG_PANEL\":\"$tag\",\"NB_DEBUG_LANG\":\"en\"}" \
    --device $CD com.nextbody.hoop > /dev/null 2>&1
  sleep 11
  open -W -a $GRAB --args $OUT/$tag.png zihuang
  echo "grabbed $tag"
done
