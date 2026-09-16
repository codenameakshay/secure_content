## 2.1.0

- Added an explicit biometric-unavailable state: the default lock screen now explains that biometrics can't be used and offers a "Try again" action. The screen stays locked until authentication succeeds.
- Removed the unused `SecureContentPolicy.clipboardClearAfter` field. It never had an effect. Pass `clearAfter` to `setSensitiveClipboard` instead.
- Fixed biometric handling: results now match the request that started them, the initial lock applies synchronously, the lifecycle state stays consistent, and `requireBiometricOnResume` and the integrity policy are honored.
- Fixed Android: modern emulator fingerprints are detected, AndroidX biometrics are tried on API 23–27, the navigation bar color is restored when protection turns off, activity state is tracked correctly, and event timestamps given as epoch values now parse correctly.
- Fixed iOS: the privacy overlay covers the windows of every scene, and `appSwitcherProtected` is emitted only after the overlay is installed.
- Fixed the sensitive clipboard: it is cleared only if its value hasn't changed since it was set.
- Fixed the default lock screen so it is fully opaque.
- Fixed state handling: a disabled scope skips integrity checks and hard block, `platformReady` is emitted after Dart subscribes, an `onEvent` exception no longer interrupts internal event handling, a disposed controller does nothing, service syncs run one at a time, and app-switcher color and image come only from sources that opted in.
- Updated the documentation for protection boundaries, recording audio, the Android app switcher, iOS screenshot detection limits, and Swift Package Manager.

## 2.0.0

- Breaking: redesigned the package around `SecureContentScope`, typed events, and controller-driven global protection, replacing the legacy `SecureWidget`/`RouteAwareState` API.
- Added biometric re-authentication, inactivity locking, integrity risk checks, sensitive clipboard controls, risk-state watermarks, and customizable lock and hard-block screens.
- Added native Android and iOS implementations, including Android 14+ screenshot callbacks and iOS app-switcher privacy overlays with optional branded imagery.
- Added Swift Package Manager support alongside CocoaPods and updated the supported toolchain baselines to Dart 3.9+, Flutter 3.41+, Android minSdk 23, and iOS 13.

## 2.0.0-beta.4

- Added `appSwitcherImageName` to `SecureContentScope` (and `ProtectionConfig`): center a host-app asset-catalog image, rendered as a white-tinted template, on the iOS app-switcher / privacy overlay so the multitasking snapshot and biometric-prompt moment show branding instead of a flat fill.

## 2.0.0-beta.3

- Added `lockScreenBuilder` and `hardBlockBuilder` to `SecureContentScope` for custom lock screen and hard-block UI.
- Migrated example Android project to built-in Kotlin (AGP 8.12 / Gradle 8.14 / Java 21).
- Bumped Pigeon from v26 to v27.
- Bumped compile/target compatibility to Java 17 for the plugin and Java 21 for the example.

## 2.0.0-beta.2

- Added Swift Package Manager (SPM) support for iOS alongside CocoaPods by converting the iOS plugin to pure Swift.
- Moved the generated Pigeon Swift API into the SwiftPM package layout (`ios/secure_content/Sources/secure_content`).
- Fixed iOS build issues and made `HostApi` methods internal to match the Pigeon-generated Swift types.
- Pinned the toolchain to Flutter 3.44.3 via FVM and added a `Makefile` for common dev tasks.
- Bumped the example Android toolchain to AGP 8.12 / Gradle 8.13 / Java 21.
- Reformatted generated Pigeon code with the Dart 3.12 formatter.

## 2.0.0-beta.1

- Breaking: redesigned API around `SecureContentScope`, typed events, and controller-driven global protection.
- Breaking: removed legacy `SecureWidget`/`RouteAwareState` API surface.
- Breaking: raised minimums to Flutter 3.41+, Dart 3.9+, Android minSdk 23, iOS 13.
- Replaced wrapper-style implementation with package-owned Android/iOS method/event channels.
- Updated Android/iOS build tooling and example app baselines for latest stable Flutter.
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
