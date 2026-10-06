# Native toolchain

Verified against primary release metadata on 2026-10-06. Versions are pinned
to a supported combination rather than mixed independently.

| Component | Selected | Current stable | Reason |
| --- | --- | --- | --- |
| Flutter | 3.47.4 | 3.47.4 | Latest stable Flutter; enables AGP 9 built-in Kotlin. |
| Android Gradle Plugin | 9.3.3 | 9.4.1 | Latest 9.3 patch; 9.3.2 fixes a documented JDK 17 lint crash in 9.3.1. |
| Gradle | 9.7.0 | 9.8.0 | Kotlin 2.4.20's published compatibility range ends at Gradle 9.7.0. |
| Kotlin | 2.4.20 | 2.4.20 | Latest stable Kotlin compiler and Gradle plugin. |
| Java host | 25 LTS | 25 LTS | Robolectric SDK 37 requires JDK 21 or newer; Gradle 9.7 supports JDK 25. |
| Java bytecode | 17 | — | Matching Java/Kotlin targets preserve Android bytecode compatibility. |
| Android compile SDK | 37 | 37 | AGP 9.3 supports API 37; minimum plugin SDK remains 23. |
| AndroidX Biometric | 1.1.0 | 1.1.0 | Newer published versions remain alpha releases. |
| AndroidX AppCompat | 1.8.0 | 1.8.0 | Direct dependency for the legacy fingerprint dialog theme preflight and example themes; compatible with Core 1.17.0. |
| AndroidX Core | 1.17.0 | 1.19.1 | Latest version retaining the fingerprint implementation needed by stable Biometric 1.1.0 on API 23–27. |
| AndroidX Fragment | 1.9.1 | 1.9.1 | Declare the directly imported FragmentActivity API rather than inheriting Biometric's old transitive version. |
| Robolectric | 4.17 | 4.17 | Latest stable JVM Android test runtime. |
| JUnit | 4.13.2 | 4.13.2 (JUnit 4) | Robolectric's JUnit 4 runner is retained. |
| Pigeon | 29.0.6 | 29.0.6 | Regenerate Dart, Kotlin, and Swift from the same schema and generator. |
| Xcode CI | 27.0 / Swift 6.4 | Swift 6.4 | GitHub's public `xcode-27` runner image is preview; the selected Xcode 27.0 compiler is stable. |
| Swift language | 5 with complete concurrency checks | — | Preserve deployment compatibility while checking actor isolation with the current compiler. |

`example/android/gradle.properties` enables built-in Kotlin and disables the new
Android DSL, which Flutter still accesses through its legacy extension. The
example selects Kotlin 2.4.20 on the plugin classpath without applying the Kotlin
Android plugin and uses `kotlin.compilerOptions` rather than deprecated
`kotlinOptions`. The plugin follows Flutter's built-in Kotlin migration, which
requires a minimum Flutter 3.44; the example uses Flutter 3.47 to enable it.
The Gradle distribution is verified using its upstream SHA-256 checksum.
Kotlin's published compatibility table lists AGP through 9.3.1. The example
uses the subsequent 9.3.3 bugfix patch because 9.3.2 fixes the JDK 17 lint
crash documented in Android issue 522845800; its build and tests are checked
against this exact combination. The newer AGP 9.4 minor is outside that range.
Consuming Android apps must use compile SDK 37 or newer and AGP 9.2 or newer,
which supports API 37.0. This does not raise the plugin's Android minimum SDK or change
the example's Flutter-managed target SDK.

Core 1.18.0 and 1.19.1 retain the `FingerprintManagerCompat` class but replace
its hardware/enrollment checks with constant `false` and its authentication
methods with no-ops. This was verified against the official AAR bytecode and
reproduced by the API 23 biometric test. Core 1.17.0 retains the implementation.
Its strict dependency constraint prevents another transitive dependency from
silently disabling API 23–27 authentication while stable Biometric remains 1.1.0.
To inspect each linked AAR, extract its `classes.jar` and run
`javap -c -p -classpath classes.jar androidx.core.hardware.fingerprint.FingerprintManagerCompat`.

API 23–27 fingerprint dialogs also require an AppCompat theme. The example's
launch and normal themes inherit `Theme.AppCompat.DayNight.NoActionBar` in
both light and dark resource sets. The plugin checks the dialog's resolved
theme before authentication and returns unavailable for unsupported themes.
AppCompat 1.8.0 declares Core 1.13.0 in its published dependency metadata and
works with the Core 1.17.0 constraint.

CI runs Dart checks, binding regeneration, Android builds, and Android unit tests
before the iOS job. The iOS job builds the example and compiles runtime tests
before `test-without-building` starts one simulator test pass. Test retries and
parallel simulator workers are disabled. Pull requests receive one workflow per
update; branch pushes do not also launch a duplicate workflow.

Legacy navigation-bar color tests run on API 23 and 30, where those setters
take effect. A separate API 37 regression checks secure-window ownership and
restoration without asserting deprecated navigation-bar color behavior.
Robolectric's API 37 native graphics runtime does not support Linux ARM64.
On that host, a temporary Gradle init script may set
`robolectric.enabledSdks=23,27,28,29,30,34` for the test task; this is a partial
local run and cannot verify the API 37 regression. The CI job uses Linux x86-64
and runs the unfiltered suite with JDK 25. No repository-level OS exception
disables that test.

Local verification on 2026-10-06 built the example debug APK with Flutter
3.47.4, AGP 9.3.3, Gradle 9.7.0, Kotlin 2.4.20, compile SDK 37, and JDK 25.
The filtered JVM run passed 48 tests with zero failures; Android lint reported
zero issues. Dependency insight confirmed the application resolves both
Core and Core KTX to 1.17.0 after adding AppCompat 1.8.0. The API 37 test
remains unverified locally and required in CI.

Use `make check`, `make android-test`, and `make ios-policy-test` before the final
device pass. `scripts/test_ios.sh` requires macOS, Xcode, and the pinned Flutter
iOS artifacts; it gathers every plugin and runtime-test Swift source.
The example and runtime-test package use iOS 15, matching Flutter 3.47's
deployment minimum. The library's iOS 13 API availability is retained for
consumers on earlier supported Flutter versions.

Sources:

- [Flutter 3.47.4 Android defaults](https://github.com/flutter/flutter/blob/3.47.4/packages/flutter_tools/lib/src/android/gradle_utils.dart)
- [Flutter built-in Kotlin migration for plugin authors](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors)
- [Kotlin Gradle/AGP compatibility table](https://kotlinlang.org/docs/gradle-configure-project.html)
- [AGP 9.3 compatibility](https://developer.android.com/build/releases/agp-9-3-0-release-notes)
- [AGP release metadata](https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/maven-metadata.xml)
- [Kotlin release metadata](https://plugins.gradle.org/m2/org/jetbrains/kotlin/android/org.jetbrains.kotlin.android.gradle.plugin/maven-metadata.xml)
- [Gradle release metadata](https://services.gradle.org/versions/current)
- [Gradle 9.7.0 checksum](https://services.gradle.org/distributions/gradle-9.7.0-bin.zip.sha256)
- [Gradle Java compatibility](https://docs.gradle.org/9.7.0/userguide/compatibility.html)
- [Temurin JDK 25 release metadata](https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture=aarch64&image_type=jdk&os=linux)
- [AndroidX Biometric release metadata](https://dl.google.com/dl/android/maven2/androidx/biometric/biometric/maven-metadata.xml)
- [AndroidX AppCompat release metadata](https://dl.google.com/dl/android/maven2/androidx/appcompat/appcompat/maven-metadata.xml)
- [AppCompat 1.8.0 dependency metadata](https://dl.google.com/dl/android/maven2/androidx/appcompat/appcompat/1.8.0/appcompat-1.8.0.module)
- [AndroidX Core release metadata](https://dl.google.com/dl/android/maven2/androidx/core/core/maven-metadata.xml)
- [Core 1.17.0 official AAR](https://dl.google.com/dl/android/maven2/androidx/core/core/1.17.0/core-1.17.0.aar)
- [Core 1.18.0 official AAR](https://dl.google.com/dl/android/maven2/androidx/core/core/1.18.0/core-1.18.0.aar)
- [AGP 9.2 API 37.0 support](https://developer.android.com/build/releases/agp-9-2-0-release-notes)
- [AndroidX Fragment release metadata](https://dl.google.com/dl/android/maven2/androidx/fragment/fragment/maven-metadata.xml)
- [Robolectric release metadata](https://repo.maven.apache.org/maven2/org/robolectric/robolectric/maven-metadata.xml)
- [GitHub runner images](https://github.com/actions/runner-images)
- [Xcode 27 runner toolchain](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
- [Apple Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
