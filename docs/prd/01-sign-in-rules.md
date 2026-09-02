# 01 · 登录注册 Sign In — rules and edges (mirrored 2026-09-01; screens are in 01-sign-in.md)

## Hard rules · 验证码与会话
01 Six digits, valid 10 minutes, single use; a new code voids the old at once.
02 No resend within 60 s; resends and wrong codes counted separately; resend cap 5 / hour / email.
03 Five wrong codes lock the email 15 minutes — on the server, sending refused too.
04 Sessions slide 90 days; a new device does not sign out the old one.
05 No password, no username, no recovery flow — the email is the recovery.
06 No health field is read at sign-in; HealthKit is asked at Onboard · 01.
07 The brand animation plays once, on the NEW branch only, shared with first launch and pairing success.

## Edge cases · 05 「出错的时候，不清屏」
1 WRONG CODE — six cells red-outlined, 6 px horizontal shake, one error haptic, "That code didn't
  work.", then cleared back to the first cell. Fifth error: "Too many tries. Try again in 15:00."
2 EXPIRED — not an error, no red: "That code has expired." and the primary becomes "Get a new code".
3 RATE LIMITED — `5 SENT · 1H WINDOW` (caution dot), "You've hit the limit. Try again in an hour." One
  sentence for every failure, so nothing reveals whether the email exists.
4 NO NETWORK — the button turns to "Sending" in place, 8 s timeout, then "No connection. Your code
  wasn't sent." Nothing cleared.
5 APPLE / GOOGLE — cancelled on the system sheet: silent back to 01. Token failure only: "Sign-in failed.
  Try email instead." and the email button moves to second.

## Before ship
! Sign in with Apple present and first (Guideline 4.8). ! Delete account reachable in-app.
! Three paths indistinguishable on the server. ! Events: AUTH_GATE_VIEW · AUTH_METHOD_TAP{APPLE|GOOGLE|
  EMAIL} · AUTH_CODE_SENT · AUTH_CODE_ERROR{REASON} · AUTH_SUCCESS{IS_NEW_USER} · AUTH_DROP{STEP}
! Acceptance: gate → home/Connect P50 ≤ 15 s; email path ≥ 85%; first-code pass ≥ 90%.
