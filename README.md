# Signal Kit

Personal SwiftUI client for downloading observations from a private home service and browsing them offline. Requires iOS 17 or later. The public client builds and tests independently with synthetic data; private companion code, credentials and personal settings are not included.

## Use

1. On trusted home Wi-Fi, enter your private server URL and dedicated app credential. Connect downloads the existing snapshot; it does **not** collect sources.
2. Configure your region/providers, explicitly refresh to load catalogues, then select the intended locations. Configure watches while connected.
3. Tap **Refresh offers at home**. One server operation collects permitted data; progress can be resumed if Wi-Fi or foreground polling stops. A failed source or download keeps earlier saved data.
4. Away from home, launch the app normally. Offers, label search, details, downloaded history and current/upcoming watch comparisons use local files, not server requests. Expired offers are hidden locally. Changes to watches/settings require a checked home connection; no offline-write queue exists.

The date window is today through the end of the next Berlin calendar week. Moving into another week does not download missing days: the app warns when saved coverage no longer covers that window. History is bounded and truncation is disclosed. Partial advertising is not inventory, branch availability or a complete product catalogue. Unknown deposit, variant, scope and price conditions stay explicit. Reference prices, especially suggested retail prices, do not establish a previous shelf price.

## Transport and storage

HTTPS retains normal platform verification. The user's accepted optional LAN HTTP transport is restricted at runtime to canonical RFC1918 IPv4 literals; public HTTP, user-info URLs and redirects are rejected. The narrow local-network ATS allowance is not a blanket ATS disable. **HTTP is not encrypted:** interception can reveal or modify preferences, observations and the bearer credential. Use only on trusted home Wi-Fi with a dedicated random app token, LAN-only firewall rules and no port forwarding/public IPv6 exposure. Never use an Apple/repository password as the token.

Credentials use per-server Keychain records, accessible only when unlocked on this device. Address selection uses UserDefaults. Offline snapshots use protected, backup-excluded Application Support files with atomic writes and a last-known-good copy. Schema, backend identity and revision checks prevent accidental cross-server/older replacement; explicit reconnect preserves displaced/unreadable data privately. Tokens are not written to snapshots. Uninstalling can lose saved data. A privacy overlay hides the UI while inactive.

## Build / tests

On macOS with Xcode and XcodeGen: `xcodegen generate`, then test scheme `SignalKit` on an available iPhone simulator. CI performs synthetic unit/UI tests, an unsigned arm64 device build and IPA validation. Test-only transport/fixtures are compiled out of release builds; no live service, geocoder or private repository is required.

CI's unsigned IPA is **not install-ready**: sign it with your own development setup. Free provisioning has limits and typically expires after seven days. Version 0.1.0/build 2 is a preview until real-device signing/Keychain, Local Network permission, trusted-LAN refresh and airplane-mode relaunch/recovery are accepted. Simulator success is not a physical-device claim.

No background monitoring, notification relay, cloud endpoint, VPN or on-phone collector is included. Deployment details and personal evidence remain in Git-ignored local documentation.
