# 05 · Dock 输入 打字/说话/照片 — rules, edges, before-ship (mirrored 2026-09-01)
Tracks: A keyboard (OPEN 0.38S · SEND 0.22S · DISMISS 0.24S · ANSWER 0.18S) · B hold to talk (HOLD 0.20S TO
ARM · RELEASE 0.22S · CANCEL Y < −56PX · ANSWER 0.18S) · C photo + text (ATTACH 0.24S · UPLOAD IN
BACKGROUND · SEND ARMS AT 100% · ANSWER 0.18S). Motion frames: 05M.

## Hard rules
01 Three slots, fixed: row 358 wide, space-between + gap 14, 48 px above the bottom
   (safe.bottom + 14 — the 10 px below it are the page-dots lane, 04B rule 02); side keys 54 × 54
   (carbon-4 + 1 px hairline); centre flex-grow, 56 high, radius 999. Left = mode, right = secondary
   action (camera at rest / send while typing). No third function on the right.
02 The centre has three shapes only: resting capsule (dot matrix breathing at 0.4 Hz), text field,
   recording chamber (132 px). The photo tray hangs above the field; it is not a fourth shape.
03 Arm after a 200 ms hold. Before that, lifting does nothing. The arm signal is one group, same
   frame: double haptic + dots collapse into a bar + capsule rises.
04 While recording the dock takes two gestures: release = send, drag up > 56 px = cancel. Side keys
   fade and stop hit-testing in the frame the chamber opens.
05 Cancel is reversible: back within −56 px re-arms; the timer never stops. Cancel writes nothing.
06 Send lights only for ≥ 1 non-blank character; with a photo, upload at 100% and ≥ 1 character. No
   bare photos, no empty messages.
07 Leaving the dock is one implementation for all three: 220 ms ease-out-back with 8 px overshoot,
   then dissolve → panel → THINKING. The keyboard starts dropping 40 ms later.
08 Messages do not land on the page: no bubbles, no thread, no local history. The only residue is the
   panel's Doto echo; the next question replaces the screen.
09 Band state never gates input: disconnected, flat, unpaired — all three slots work.
10 The dot matrix is a spec: 96 × 32, 14 × 5, r 1.3, pitch 6.4, carbon rgb(0 0 0 / 78%), outer two
   rows/cols at 0.55 / 0.25. Breathes at 0.4 Hz; on keyboard it wipes left → right into a caret.

## Edge cases · 06 「出问题的时候，输入口不许消失」
1 MIC DENIED — capsule amber outline `MICROPHONE OFF`; "Typing still works. / Turn the mic on in
  Settings."; outlined Open Settings. No system prompt the second time.
2 TOO SHORT — < 0.6 s is a slip: `0.3S · TOO SHORT` on the capsule for 1.2 s, "Hold, say it, then let go."
3 NO SPEECH — transcript empty: `NOTHING HEARD`, "Say it again, or type it." Nothing is sent.
4 UPLOAD FAILED — thumbnail amber-bordered, caption stays, send stays dark: `UPLOAD FAILED`, "Tap the
  photo to retry, or remove it."
5 OFFLINE — `NO CONNECTION`, "It stays here. Send it when you're back." The message never leaves the dock.
6 INTERRUPTED — call or alarm took the mic: `INTERRUPTED AT 0:07`, "Not saved. Say it again when you're free."

## Before ship
! 274 px keyboard offset must be read from the system. ! 200 ms / 56 px untested. ! Max recording
  length undecided. ! ASR on-device vs server conflicts with 「不存音频」. ! Track A needs the
  dissolve / THINKING frame. ! VoiceOver: keyboard is the full equivalent; Reduce Motion → 120 ms fades.
! Photo retry policy undecided. ! C·07 answer has two optional blocks (source chip, "已记入今天的 fuel").
! Events: DOCK_MODE{FROM,TO} · KB_OPEN{MS} · MSG_SEND{TYPE,CHARS,HAS_PHOTO} · VOICE_ARM{MS} ·
  VOICE_SEND{DUR_MS,ASR_MS,CHARS} · VOICE_CANCEL{DUR_MS,REASON} · PHOTO_ATTACH · PHOTO_UPLOAD{MS,BYTES,OK}
  · ANSWER_IN{MS,TYPE} · INPUT_FAIL{REASON}
! Acceptance: arm → recording ≥ 98%; false cancel ≤ 2%; release → answer P50 ≤ 1.2 s / P90 ≤ 2.5 s.
