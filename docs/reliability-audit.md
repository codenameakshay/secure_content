# Reliability audit

Baseline: `72e823162c1766f6cb34f0cdf9ca9417bd1a1b62` (`2.1.0`).

This audit covers the Flutter API, platform channel, Android and iOS plugins,
example, packaging, and CI. It combines source inspection, regression tests,
adversarial state sequences, and independent review. It does not establish
that every possible device or operating-system behavior is defect-free.

## Coverage

The baseline contains 141 tracked files. The first pass inspected each runtime
subsystem and its callers. The second pass checked ordering, ownership,
background execution, unsupported platforms, and failure recovery.

| Area | Baseline files | Audit focus |
| --- | ---: | --- |
| Dart runtime | 8 | Scope state, controller disposal, service serialization, events, policy, platform support |
| Dart tests | 5 | Existing assertions, missing failure cases, channel mocks |
| Android plugin and build | 7 | Window ownership, biometric API levels, clipboard lifetime, activity and engine teardown |
| iOS plugin and packaging | 5 | Capture and scene lifecycle, window ownership, clipboard expiration, native configuration |
| Generated bindings and registrants | 6 | Pigeon schema, channel names, field order, platform registration |
| Example source and platform scaffolding | 60 | API callers, host permissions, build configuration, supported launch paths |
| Root docs, tooling and CI | 17 | Public behavior, SDK pin, verification commands, package contents |
| Media and icons | 33 | Referenced asset inventory; binary artwork is not executable code |

## Confirmed defects and fix accounting

The final verification record below tracks the tests and reviews for these fixes.

| ID | Failure scenario | Correction |
| --- | --- | --- |
| D1 | An old capture query returns after a newer recording event. | Preserve the newer capture state. |
| D2 | Authentication finishes after the app enters the background. | Keep content locked and require fresh authentication on return. |
| D3 | A locked or blocked child retains keyboard focus and accessibility semantics. | Isolate protected input and semantics while covered. |
| D4 | Keyboard or scroll activity does not reset inactivity tracking. | Count supported non-pointer activity. |
| D5 | Resume restarts the inactivity timer after a long suspension. | Enforce elapsed inactivity before exposing content. |
| D6 | An old biometric channel failure arrives after a new request starts. | Complete only the request that owns the failure. |
| D7 | The first sensitive frame appears before native setup finishes, or setup fails asynchronously. | Keep an opaque cover until setup succeeds; report errors and retry on resume. |
| D8 | Web code calls unsupported `dart:io` platform operations. | Return the unsupported-platform fallback without calling native channels. |
| D9 | An out-of-range numeric event timestamp throws during decoding. | Treat invalid timestamps as absent. |
| D10 | Equal or backward wall-clock timestamps make source priority ambiguous. | Order source updates with a monotonic sequence. |
| D11 | A backwards wall-clock adjustment extends the inactivity deadline. | Use monotonic elapsed time as a minimum while retaining wall time for suspension. |
| D12 | A completed service queue retains an old async zone, stalling configuration when widget tests switch clocks. | Release the queue when idle without releasing a newer pending operation. |
| A1 | AndroidX constructs a biometric-only prompt without a negative button on API 23–29. | Supply the required cancel action. |
| A2 | Plugin attachment clears a host-owned secure window flag. | Preserve host protection and restore only plugin-owned state. |
| A3 | Navigation-bar color changes while protection is disabled or restores an obsolete color. | Apply color only during protection and release each saved value after restoration. |
| A4 | Engine teardown cancels the only clipboard expiry callback. | Preserve or complete owned clipboard cleanup. |
| A5 | An activity detaches with an authentication prompt still pending. | Cancel the prompt and suppress stale native callbacks. |
| A6 | Clipboard expiry runs before a resumed window gains clipboard access. | Retain pending cleanup and retry after focus returns. |
| A7 | A newer clipboard copy contains the same text as an expired sensitive copy. | Check a per-copy ownership token, including an API 23 fallback. |
| A8 | Two Flutter engines protect one window and one engine disables protection. | Aggregate protection owners before restoring host window state. |
| A9 | A very large clipboard TTL overflows the native scheduler deadline. | Saturate the deadline without wrapping to an immediate callback. |
| I1 | The example requests Face ID without a usage description. | Add the host permission text and installation guidance. |
| I2 | iOS suspends the app before its clipboard timer runs. | Use operating-system clipboard expiration. |
| I3 | A user copies the same text again before an old clipboard timer expires. | Track clipboard ownership rather than text equality alone. |
| I4 | Native privacy configuration changes while a cover already exists. | Reconcile cover presence, color, and image immediately. |
| I5 | A scene or window changes state independently of the application. | Apply privacy protection to the affected windows and preserve other scenes' covers. |
| I6 | One plugin instance removes another engine's privacy covers. | Track per-instance overlay ownership. |
| I7 | A transparent app-switcher color exposes content beneath the privacy cover. | Make native privacy backgrounds opaque. |
| I8 | Capture changes on an external screen disagree with the main screen. | Reconcile per-screen covers and aggregate capture events. |
| I9 | Clipboard cleanup reads a replacement entry before checking ownership. | Check the change count before reading text to avoid a foreign paste prompt. |
| I10 | An engine disappears while native authentication is pending. | Invalidate its authentication context and ignore stale completion. |

## Verification record

### Independent review

Two GPT-6.1 Sol review rounds checked correctness/specification and repository
standards in parallel. Round one caught release-mode accessibility tracking,
clock rollback, multiple resumed Android activities, Swift initializer visibility,
and discarded iOS test diagnostics. Round two caught incomplete clipboard
cleanup after engine destruction and an incorrect ordering oracle in a new stress
test. The fixes and their regressions are included; native runtime verification
remains a separate CI gate.

A Luna comment review removed redundant narration. Generated bindings were
checked against the Pigeon schema rather than edited by hand.

The service stress suite uses seeds `0x51A7`, `0xC0FFEE`, `0xBAD5EED`, and
`0x7E57`, with 512 random actions and one final synchronization per seed.
The passing run exercised 2,052 actions, 1,887 live controller operations,
and 156 replacements of disposed controllers. Native replies are delayed,
every 29th configuration fails, and the suite checks recovery, final state,
and a maximum of one native configuration in flight. A separate regression
checks last-writer priority when two sources have unequal update counts.

### Executed checks

The final local `make check` passes with the repository-pinned Flutter 3.44.3:
formatting, static analysis, all 44 package tests, and the example test.
The package suite includes four scope seeds (`0x5eed`, `0x1bad`, `0xc0ffee`,
`0x7a11`) with 256 lifecycle/policy actions each, totaling 1,024 actions.
It also covers initial setup failure/retry, stale replies, protected input,
accessibility activity, and authentication across real background transitions.

The local host runs Linux ARM64 and has no iOS simulator. Native simulator
results must come from the macOS CI job. The first CI build caught an invalid
optional chain on Swift's nonoptional `keyEnumerator()`; this is corrected.
Native CI on the final revision remains required before marking the PR ready.

Android CI on `66db971` passed the Dart gates, example APK build, and native
unit tests. The iOS example build and policy tests also passed. The simulator
suite passed its first two synchronous tests, then stalled in the first async
clipboard test. All four duplicate/stale runs were cancelled. The clipboard
tests now use bounded XCTest waits instead of async actor sleeps; this correction
requires a new simulator run. CI runs once per PR revision, cancels superseded
runs, reuses the pinned Flutter installation, caps each job at 15 minutes, and
caps the simulator step at five minutes with individual test timeouts.

The four Foundation-only native policy tests pass with
`swift test --package-path ios`. These do not validate UIKit or Flutter engine
integration. Android unit-test execution is blocked locally because the installed
NDK directories lack `source.properties`; CI runs the Android build and Robolectric
suite. CI also builds the iOS example and runs the UIKit/pasteboard simulator
suite, retaining its `.xcresult` bundle and privacy-cover image attachment.

Pigeon 27.1.0 regenerated all three platform bindings without differences.
The audit used temporary output files and retained the existing generated code.

## Limits and rejected hypotheses

- Controller disposal already removes its source in the serialized service
  queue. The audit did not find a stale controller update that resurrects it.
- Integrity checks deliberately report heuristic risk. Test-key firmware,
  emulators, simulators, and debuggers can be flagged without proving compromise.
- iOS reports screenshots after they occur. This package cannot prevent them.
- Visual capture protection does not silence recorded audio.
- Custom lock and hard-block builders remain responsible for an opaque,
  full-size cover, as documented in the public API.
- Android restricts clipboard access for background apps. Device behavior and
  operating-system cleanup remain relevant to clipboard lifetime guarantees.
