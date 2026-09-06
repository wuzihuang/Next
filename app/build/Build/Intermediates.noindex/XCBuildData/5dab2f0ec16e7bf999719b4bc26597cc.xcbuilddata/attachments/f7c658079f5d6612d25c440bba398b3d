#!/bin/sh
if [ "$PLATFORM_NAME" != "iphoneos" ]; then echo "skip on $PLATFORM_NAME"; exit 0; fi
DST="$BUILT_PRODUCTS_DIR/$FRAMEWORKS_FOLDER_PATH"; mkdir -p "$DST"
for FW in "$PROJECT_DIR"/Frameworks/*.framework; do
  BIN="$FW/$(basename "$FW" .framework)"
  # Static archives are already linked into the executable; installd rejects them under Frameworks/.
  if file -b "$BIN" | grep -q "ar archive"; then echo "skip static $(basename "$FW")"; rm -rf "$DST/$(basename "$FW")"; continue; fi
  rsync -a --delete "$FW" "$DST/"
  if [ -n "$EXPANDED_CODE_SIGN_IDENTITY" ]; then
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$DST/$(basename "$FW")"
  fi
done

