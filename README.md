# secure_content 3.0.0 device validation evidence

Evidence for the 3.0.0 device validation PR (branch `fix/3.0.0-device-validation`).
This orphan branch holds screenshots and log excerpts only. Do not merge it.

- `android-api28/`: Pixel 3 AVD, Android 9 (API 28), Google APIs arm64. Screenshots come
  from the emulator host framebuffer because FLAG_SECURE makes device-side `screencap` empty.
- `android-api36/`: Pixel 6 AVD, Android 16 (API 36), Google APIs arm64.
- `ios27/`: iPhone 17 simulator, iOS 27.0, Xcode 27.0. `switcher_snapshot_*` are the
  app-switcher snapshots iOS stored in the app container, converted from KTX.
- `logs/`: logcat, `flutter run`, unified-log, and XCTest excerpts referenced by the report.

Host: macOS arm64 with a load average between 50 and 600 from other work. Emulator input
lag and the two ANRs are attributed to that load in the report.
