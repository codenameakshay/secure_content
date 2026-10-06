#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_root="${FLUTTER_ROOT:-}"
if [[ -z "$flutter_root" ]]; then
  flutter_bin="$(command -v flutter || true)"
  if [[ -z "$flutter_bin" ]]; then
    echo "flutter must be on PATH or FLUTTER_ROOT must be set" >&2
    exit 1
  fi
  flutter_root="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
fi

flutter_framework="$flutter_root/bin/cache/artifacts/engine/ios/Flutter.xcframework"
if [[ ! -d "$flutter_framework" ]]; then
  echo "Flutter.xcframework not found at $flutter_framework; run flutter build ios --simulator first" >&2
  exit 1
fi

package_dir="$(mktemp -d "${TMPDIR:-/tmp}/secure-content-ios-tests.XXXXXX")"
result_bundle="${IOS_TEST_RESULTS_PATH:-${RUNNER_TEMP:-$repo_root/build}/secure-content-ios-tests.xcresult}"
mkdir -p "$(dirname "$result_bundle")"
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "$package_dir/Sources/SecureContent" "$package_dir/Tests/SecureContentRuntimeTests"
cp "$repo_root/ios/secure_content/Sources/secure_content/SecureContentPlugin.swift" \
  "$repo_root/ios/secure_content/Sources/secure_content/SecureContentApi.g.swift" \
  "$repo_root/ios/secure_content/Sources/secure_content/SecureContentNativePolicy.swift" \
  "$package_dir/Sources/SecureContent/"
cp "$repo_root/ios/Tests/Runtime/SecureContentPluginRuntimeTests.swift" \
  "$package_dir/Tests/SecureContentRuntimeTests/"
cp -R "$flutter_framework" "$package_dir/Flutter.xcframework"

cat > "$package_dir/Package.swift" <<'PACKAGE_MANIFEST'
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "SecureContentRuntimeTests",
  platforms: [.iOS(.v13)],
  targets: [
    .binaryTarget(name: "Flutter", path: "Flutter.xcframework"),
    .target(
      name: "secure_content",
      dependencies: ["Flutter"],
      path: "Sources/SecureContent"
    ),
    .testTarget(
      name: "SecureContentRuntimeTests",
      dependencies: ["secure_content", "Flutter"],
      path: "Tests/SecureContentRuntimeTests"
    ),
  ],
  swiftLanguageVersions: [.v5]
)
PACKAGE_MANIFEST

simulator_id="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
available = [device for runtime in devices.values() for device in runtime
             if device.get("isAvailable") and device["name"].startswith("iPhone")]
booted = next((device for device in available if device.get("state") == "Booted"), None)
selected = booted or (available[0] if available else None)
if selected is None:
    raise SystemExit("No available iPhone simulator found")
print(selected["udid"])
')"

scheme="$(cd "$package_dir" && xcodebuild -list -json -quiet | python3 -c '
import json, sys
listing = json.load(sys.stdin)
container = listing.get("project", listing.get("workspace", {}))
schemes = container.get("schemes", [])
selected = next((scheme for scheme in schemes if "RuntimeTests" in scheme), None)
if selected is None:
    raise SystemExit("Xcode did not expose the SecureContentRuntimeTests package scheme")
print(selected)
')"

(cd "$package_dir" && xcodebuild test \
  -scheme "$scheme" \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -destination-timeout 60 \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 15 \
  -maximum-test-execution-time-allowance 30 \
  -resultBundlePath "$result_bundle" \
  CODE_SIGNING_ALLOWED=NO)
