# 12 · 设备 Device — rules, edges, before-ship (mirrored 2026-09-01)

## Hard rules
01 Every row points at a real SDK key or method; otherwise delete it or move it to 待决.
02 Settings flow is listDeviceSettings() → readDeviceSetting(key) → writeDeviceSetting(setting); the UI
   re-renders from the write's readback, never optimistically. support === 'unsupported' → row not
   rendered, not shown as failure.
03 Range constraints are the iOS ∩ Android set: sedentary interval 30–240 min, end > start, interval <
   (end − start); heartRateAlarm 30–250 bpm, lower < upper; healthReminder 1–255. Blocked at input.
04 Sedentary reminder never shows weekdays (Android lacks the mask). Time window and interval only.
05 Alarms use the new-alarm API (mode 0 delete / 1 set / 2 read). Capacity is `?` until the first
   read; demo ceiling 20, this G70's real cap only after a refused write or a full table. Add = write
   then confirm; on failure roll the table back and state the limit. Scene stays 0 — screenless band
   alarms vibrate only. Find-the-wrist is a sheet (START then STOP), not `.findBand`.
06 Automatic measurement is a second-level page, not one switch: readAutoMeasureSetting() returns one row
   per funType 0–8; isSlotModify / isIntervalModify decide what is editable.
07 Battery binds the batteryData event, no polling. isPercent === false → 0–4 bars, days / LEFT hidden; never
   derive a percent from bars. Remaining days live on the battery trend (`Destination.battery`) from
   the learned unplugged slope (`BatteryDrainMath.left`), same silence as EST · EMPTY. Never the spec pack.
08 OTA is three-state: completed / failed / versionUnverified. The third has its own copy pointing at
   「去核对手环上的版本」. Pre-check via checkFirmwareUpdate().blockedReason; battery gate > 30%.
09 Commands are serial; a write during a measurement returns DEVICE_BUSY — queue and say so. Android
   writes time out ≈ 12 s → roll back, no endless spinner.
10 Identity: DEVICE NO. is DeviceVersion.deviceNumber (never SN); BLUETOOTH label is per platform (MAC /
   UUID) and is not a cross-platform id. The block shows while disconnected.

## Edge cases · 05 「固件说了算，UI 只负责如实转述」
1 LEVEL ONLY — four bars (3 lime + 1 grey) · `3 OF 4 BARS` · "This firmware reports level, not percent."
  LEFT / 「还能撑几天」 is not rendered — bars are not a percent.
2 UNSUPPORTED — the row is simply gone (here Wear detection). Not greyed, no 「不支持」.
3 WRITE CLAMPED — Move reminder `45 MIN` · `YOU ASKED FOR 60` (amber) · "THE BAND SET WHAT IT COULD. THIS
  IS ITS ANSWER, NOT OURS." Render the readback.
4 DEVICE BUSY — amber-bordered card `DEVICE BUSY` · "A measurement is running. Your change is queued and
  will go through when it finishes." Switch springs back with the reason.
5 OTA UNVERIFIED — amber card `VERSION UNCONFIRMED` · `2.4.1 ? 2.5.0` · "The update finished but we could
  not read the new version back. Check the band before trying again."

## Before ship
! LEFT is the learned unplugged slope on the battery trend, or it is absent. Never write a day count
  from the spec pack, 150 mAh, or bars.
! disconnectAlert has no capability bit (may read unknown forever): on, off, or hidden — pick one.
! wearDetection has no read on Android; initial value may be empty.
! "Why won't it connect?" page not drawn. ! Alarms and Automatic measurement pages not drawn (built as
  sheets per F1 D). ! Forget → reconnect path undecided.
! Events: DEV_OPEN{STATE,BATT} · DEV_SETTING_WRITE{KEY,OK,CLAMPED} · DEV_RECONNECT{MS,OK,REASON} ·
  DEV_OTA_START{FROM,TO} · DEV_OTA_END{RESULT,MS} · DEV_DISCONNECT · DEV_FORGET
! Acceptance: DEV_SETTING_WRITE OK ≥ 97%, CLAMPED < 3%; versionUnverified tracked separately.
