# Android inactive privacy cover evidence

Evidence for the Android app switcher cover PR (branch `feat/android-inactive-privacy-cover`).
This orphan branch holds screenshots and log excerpts only. Do not merge it.

All screenshots come from the emulator host framebuffer (`adb emu screenrecord screenshot`),
because FLAG_SECURE blanks device-side `screencap`. Landscape app captures are rotated upright;
the host framebuffer stores them in portrait.

- `android-api36/`: `sc_api36`, Pixel 6 AVD, Android 16 (API 36), gesture navigation, Pixel launcher.
- `android-api28/`: `sc_api28`, Pixel 3 AVD, Android 9 (API 28), three-button navigation.
- `before_*`: example app built from `origin/main` at `c136ceb` (3.0.0 changes only version strings since then).
- `after_*`: example app built from the PR head `3991696`.
- `measure/` and `logs/`: temporary builds with log lines, used to choose the signal. They are
  not part of the PR. `recents_key_15fps_contact_sheet.png` and `gesture_hold_cover.png` come
  from the first implementation commit plus logs. `cold_start_initial_unfocused_variant_*` comes
  from the reverted variant that treated a new window as unfocused.

Host: macOS arm64 shared with other sessions; load averages ranged from 4 to 160, which
stretches absolute timings. Compare orderings, not durations, in `recents_key_under_load_api36.txt`.
