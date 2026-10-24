# NextBody HOOP · Android

A 1:1 Kotlin + Jetpack Compose port of the iOS app in `../app/NextBody` (AI stays off, as on iOS).
Same Supabase backend, same design tokens, fonts, copy (`assets/l10n/zh-Hans.json` is the iOS table)
and the same pages, sheets and takeovers. One Kotlin file per Swift file, same names.

## Differences from iOS by design

- **Sign-in:** Google + email code. There is no Apple sign-in.
  - Google uses Android Credential Manager. Its `serverClientId` is the Web OAuth client of GCP project `next-507706` (`nb.googleWebClientId` in `gradle.properties`). It is a public id; the secret in `key/` is never used.
  - **Two console steps** are still needed before a Google sign-in can complete (see "Turning on Google" below).
- **Health:** Health Connect replaces Apple Health.
  - It reads height and weight only.
  - Sex and birthday are always typed in. Anything Health Connect doesn't have falls back to manual entry.
- **Band:** `VeepooBand` drives the vendor's Android SDK (github.com/HBandSDK/Android_Ble_SDK).
  - The binaries are in `app/libs/` and `app/src/main/jniLibs/`; the docs are in `vendor/`.
  - Emulators and debug walks use `MockBand` and the seeded day, exactly like the iOS simulator.
  - It has not been tried against a physical band yet. See the "Unverified" notes in `band/VeepooMapping.kt`.
- **Live Activity:** an ongoing notification instead.
- **Remote push:** not set up (no FCM). Notifications are local only.

## Build and run (on the Mac)

```sh
. ~/.nb-android-env                      # JDK 21 + Android SDK
./gradlew :app:installDebug              # emulator: `emulator -avd NextBody`
./gradlew :app:testDebugUnitTest
```

### Debug launch switches

These are the twins of the iOS `SIMCTL_CHILD_NB_DEBUG_*` switches. Pass them as intent extras:

```sh
adb shell am start -n com.nextbody.hoop/.app.MainActivity \
  -e NB_DEBUG_STAGE root -e NB_DEBUG_ROUTE vitals.sleep
```

- **Common switches:**
  - `NB_DEBUG_STAGE` (`gateSignIn` / `gateConnect` / `gateOnboarding` / `root`)
  - `NB_DEBUG_ROUTE`, `NB_DEBUG_SHEET`, `NB_DEBUG_TAKEOVER`, `NB_DEBUG_MEASURE`, `NB_DEBUG_HOME_SLOT`
  - `NB_DEBUG_SIGN_STEP`, `NB_DEBUG_CONNECT_STEP`, `NB_DEBUG_ONB_STEP`, `NB_DEBUG_EDGE`
- **Turning the seed off:** `adb shell setprop debug.nb.seed 0` makes an emulator use the real account and the real band adapter. For example, sign in with the review account `demo@nextbody.ai` and code `202610`.

## Turning on Google

1. **Google Cloud:** in project `next-507706`, create an **Android** OAuth client for package `com.nextbody.hoop` with the signing SHA-1.
   - Debug keystore on this Mac: `8A:83:3A:77:2A:23:93:6D:AD:4B:C5:10:83:F1:86:8B:BA:E6:90:7F`.
   - Add the release key's SHA-1 too.
2. **Supabase:** in Auth › Providers › Google, add the Web client id `285632967349-hl1a8q3l058ep1kmm4c2jts6ep3df3io.apps.googleusercontent.com` to *Client IDs*, next to the iOS one. The ID token's `aud` is the Web client.
