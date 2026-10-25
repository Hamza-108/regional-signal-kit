# Regional Signal Kit

A lightweight iOS client for regional observations, configurable subscriptions and event history. Connect it to your own compatible, authenticated HTTPS service. No server address, account credential, analytics or collection implementation is bundled.

## Client

- SwiftUI, iOS 17+, a small MVVM structure.
- Region and location configuration, provider selection, observation search, subscriptions and history.
- Explicit scope, freshness, package and price-condition information. Data coverage depends on the connected service; advertising is not an inventory guarantee.
- Credentials in Keychain; connection address in local settings. No external geocoder is contacted by this client.
- Event history is separate from push delivery. This free-signing build does not claim an APNs entitlement.

## Build

The standard macOS Actions job generates the Xcode project with XcodeGen, runs synthetic unit/UI tests, builds an unsigned arm64 device app and validates `Payload/SignalKit.app` inside the IPA. Download `SignalKit-unsigned` from a successful workflow run. Public builds require no private dependencies, backend connection or signing secrets.

An unsigned IPA must be re-signed and provisioned before installation. Free personal signing normally expires after seven days and has device/app limits. Compilation and simulator tests are not evidence of physical-device installation or notification receipt.

For local macOS builds: `xcodegen generate`, then open the generated project. Linux can edit source, but iOS SDK compilation requires macOS/Xcode. The public source remains inspectable; neutral naming is not a security boundary.
