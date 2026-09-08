# Next

The NextBody HOOP iOS app, health backend and storefronts.

- `app/NextBody`: SwiftUI application. `BandService` has device and simulator adapters;
  publication, refresh, phone execution and health snapshot modules own their respective
  request lifetimes. `app/Package.swift` builds the portable behavior tests.
- `supabase/functions`: authenticated requests and the explicit AI workflow. Simple chart
  sources use the same registered health reads as model tools.
- `supabase/migrations`: immutable database history. Current function definitions are
  generated from a complete local rebuild, not maintained as a second SQL source.
- `shopify-theme` and `shopify-web`: Liquid and Hydrogen storefronts. They share cart
  calculation rules but keep their own presentation and storage; see
  [the storefront README](shopify-web/README.md).

Domain vocabulary is in [CONTEXT.md](CONTEXT.md), decisions in [docs/adr](docs/adr), and
historical build/release notes in [docs/STATUS.md](docs/STATUS.md).

## Local verification

Run from the repository root with Xcode, Swift, Deno and Node installed:

```sh
swift test --package-path app
deno test --allow-read --allow-env --config supabase/functions/deno.json supabase/functions
npm run lint
npm --prefix shopify-web run test:shop
xcodebuild -project app/NextBody.xcodeproj -scheme NextBody -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The server tests use controlled adapters and do not need production credentials. UI and
real-band behavior require the Xcode UI test target or a connected device in addition to
the portable Swift tests. Database migrations need the isolated PostgreSQL checks in
[the development guide](supabase/scripts/dev/README.md#inspecting-the-current-database-definitions-locally).

For app development, open `app/NextBody.xcodeproj`. A DEBUG build can point its Edge
Functions at a local host using `app/Local.xcconfig.example`; AI requests still go through
the backend. Database migrations, Edge Functions and the app have independent release
steps. Passing local verification does not deploy them.

Vendor BLE SDK: [HBandSDK/iOS_Ble_SDK](https://github.com/HBandSDK/iOS_Ble_SDK)
