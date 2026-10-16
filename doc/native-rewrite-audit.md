# Native rewrite audit

Baseline: `66db971` (the reliability fixes in PR #18).

The audit covers Kotlin and Swift sources, generated bindings, native manifests,
Android build files, iOS packaging, example hosts, and native test infrastructure.
The baseline has 81 tracked files under the four native directories. Icon assets
and launch resources remain unchanged.

## Findings and corrections

| Area | Failure or maintenance problem | Correction |
| --- | --- | --- |
| Android authentication | Duplicate terminal callbacks emit multiple outcomes. | Consume request ownership before sending the result. |
| Android authentication | AndroidX silently ignores requests after fragment state is saved. | Reject the request with an unavailable outcome before creating a prompt. |
| Android authentication | Engines can replace callbacks before cancellation drains, including across activity recreation. | Keep the lease with the retained ViewModelStore until its terminal callback or final host destruction. |
| Android authentication | An incompatible activity theme crashes the API 23–27 fingerprint dialog asynchronously. | Check the dialog theme before requesting authentication and use AppCompat themes in the example. |
| Android lifecycle | Engine teardown sends events to the detached messenger and retains clipboard references. | Disconnect the event sink first and retain only pending cleanup state. |
| Android window ownership | Registry duplicates enabled flags and allocates filtered lists. | Track active owners in insertion order and restore the host's original state. |
| iOS authentication | Duplicate or obsolete completions can send terminal events. | Consume the request generation and reject cancelled or replaced contexts. |
| iOS capture | Screen-only observation uses deprecated APIs on modern iOS. | Observe scene capture traits on iOS 17+, with screen fallback notifications. |
| iOS window ownership | Configuration changes omit aggregate coverage events; removed covers stay detached. | Reconcile events after configuration and reattach owned covers. |
| iOS integrity | A fixed probe path can overwrite an existing file. | Use a unique path with exclusive creation. |
| Swift packaging | Language mode `5.9` is invalid. | Select language mode `5` and enable complete concurrency checking. |
| Android dependencies | Core 1.18+ removes the fingerprint implementation required by stable Biometric on API 23–27. | Constrain Core to 1.17.0 and exercise real AndroidX fingerprint authentication in Robolectric. |
| Native bridge | Generator and native toolchains are outdated. | Regenerate all bindings with Pigeon 29.0.6 and preserve native callback ordering. |
| Verification | CI runs duplicate workflows and the test runner lists individual Swift files. | Run one PR workflow, gather all native sources, and build tests before the device pass. |

The public Dart methods and event names remain unchanged. Kotlin and Swift use
typed internal events. UIKit work belongs to the main actor. Generated Pigeon
code remains generator-owned.

## Toolchain

The [toolchain record](native-toolchain.md) contains the selected versions,
compatibility limits, and primary sources. Android consumers require compile SDK 37. The example uses AGP 9.3.3. Flutter 3.44 is the plugin minimum. The example and CI use
Flutter 3.47.4, whose iOS deployment minimum is 15.

## Review and verification

Independent GPT-6.1 Sol review found the iOS screen-fallback observation gap and
Android cross-engine authentication ownership problem. Both received changes
and regression tests. A separate comment review found no new runtime narration
or correctness-hiding suppressions. Stale template comments were removed.

Completed locally:

- Flutter 3.47.4: formatting, analysis, 44 package tests, and one example test.
- Swift 6.4: six portable policy tests with 22 parameter executions, complete
  concurrency checking, and warnings treated as errors.
- Android: 48 Robolectric tests passed across SDKs 23, 27, 28, 29, 30, and 34;
  lint reported zero issues, and the example debug APK built successfully.
  The SDK 37 test requires the x86 CI host because its Robolectric native runtime
  does not support this Linux ARM64 host.
- Pigeon 29.0.6: regeneration leaves all three checked-in bindings unchanged.
- Swift source syntax, package manifests, Ruby syntax, shell syntax, and diff
  whitespace checks.

CI passed all 49 Android tests, including SDK 37, along with lint and the APK
build. Xcode 27 compiled the iOS example and runtime suite. The first simulator
pass executed 14 tests: ten passed and four clipboard tests failed with
pasteboard authorization errors in the unhosted XCTest process. The harness
now uses a UIKit app host. CI on `3c90eef` passed all 14 simulator tests,
including every clipboard case, and all six portable policy tests. The runtime
suite completed in about 24 seconds with zero failures; the full iOS job,
including setup, builds, simulator startup, and artifacts, took 12m40s.
The CI step timeout also interrupted result-bundle finalization; the runner
now has more time to save results while individual test waits stay bounded.
The exported privacy-cover image from that run was transparent because it
rendered a hidden test window. The fixture now renders the visible cover and
checks its pixel color and opacity before attaching the image. This is a test
artifact correction; production code is unchanged.
Swift syntax checks on Linux do not typecheck UIKit or Flutter. CI builds both
the example and runtime test bundle before running tests. Each invocation uses
one simulator pass, with retries and parallel workers off.

## Platform limits

Screenshot detection on iOS occurs after capture. Integrity checks are heuristic.
Android background clipboard access can defer cleanup until focus returns.
Biometric hardware and physical-device capture behavior need device coverage
beyond a simulator. The audit does not establish defect-free behavior on every
supported OS and device.
