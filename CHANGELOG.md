## 2.0.0-beta.1

- Breaking: redesigned API around `SecureContentScope`, typed events, and controller-driven global protection.
- Breaking: removed legacy `SecureWidget`/`RouteAwareState` API surface.
- Breaking: raised minimums to Flutter 3.41+, Dart 3.9+, Android minSdk 23, iOS 13.
- Replaced wrapper-style implementation with package-owned Android/iOS method/event channels.
- Updated Android/iOS build tooling and example app baselines for latest stable Flutter.\
- Added Android and iOS biometric re-auth APIs and events.
- Added inactivity auto-lock support through `SecureContentPolicy` and scope-level lock overlays.
- Added integrity risk checks (root/jailbreak/debugger/emulator heuristics) with soft mode events and hard-block mode behavior.
- Added sensitive clipboard APIs with TTL-based auto-clear and clipboard lifecycle events.
- Added risk-state watermark support (shown during capture/lock/background/integrity risk states).
- Added Android 14+ screenshot callback support and explicit platform documentation.
- Updated Android plugin/tooling setup (AGP, Kotlin, build tools) and improved run/build compatibility.
- Refreshed README and example docs to match v2 API and current feature matrix.

## 1.0.1

- Updated to Flutter v3.29.2

## 1.0.0

- First stable release
- Updated to Flutter v3.22.1

## 0.1.0

- Working for both Android & iOS
- Removed callback methods for Android (no need)

## 0.0.11

- Initial release
- Supports Android & iOS
