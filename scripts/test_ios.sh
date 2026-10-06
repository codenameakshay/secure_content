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
  flutter_root="$(python3 -c 'import os, sys; print(os.path.dirname(os.path.dirname(os.path.realpath(sys.argv[1]))))' "$flutter_bin")"
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
cp "$repo_root/ios/secure_content/Sources/secure_content/"*.swift \
  "$package_dir/Sources/SecureContent/"
cp "$repo_root/ios/Tests/Runtime/"*.swift \
  "$package_dir/Tests/SecureContentRuntimeTests/"
cp -R "$flutter_framework" "$package_dir/Flutter.xcframework"

cp "$repo_root/scripts/ios-runtime-package.swift" "$package_dir/Package.swift"

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

(cd "$package_dir" && xcodebuild build-for-testing \
  -scheme "$scheme" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$package_dir/DerivedData" \
  CODE_SIGNING_ALLOWED=NO)

(cd "$package_dir" && xcodebuild test-without-building \
  -scheme "$scheme" \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$package_dir/DerivedData" \
  -parallel-testing-enabled NO \
  -retry-tests-on-failure NO \
  -resultBundlePath "$result_bundle" \
  CODE_SIGNING_ALLOWED=NO)
