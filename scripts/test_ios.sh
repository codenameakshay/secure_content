#!/usr/bin/env bash
set -euo pipefail

build_only=false
case "${1:-}" in
  "") ;;
  --build-only) build_only=true ;;
  *) echo "Usage: test_ios.sh [--build-only]" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  echo "Usage: test_ios.sh [--build-only]" >&2
  exit 2
fi

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

project_dir="$(mktemp -d "${TMPDIR:-/tmp}/secure-content-ios-tests.XXXXXX")"
trap 'rm -rf "$project_dir"' EXIT
ruby "$repo_root/scripts/ios-runtime-project.rb" "$project_dir" "$repo_root" "$flutter_framework"
project_path="$project_dir/SecureContentRuntimeTests.xcodeproj"

xcodebuild build-for-testing \
  -project "$project_path" \
  -scheme SecureContentRuntimeTests \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$project_dir/DerivedData" \
  CODE_SIGNING_ALLOWED=NO

if [[ "$build_only" == true ]]; then
  exit 0
fi

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

result_bundle="${IOS_TEST_RESULTS_PATH:-${RUNNER_TEMP:-$repo_root/build}/secure-content-ios-tests.xcresult}"
mkdir -p "$(dirname "$result_bundle")"
xcodebuild test-without-building \
  -project "$project_path" \
  -scheme SecureContentRuntimeTests \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$project_dir/DerivedData" \
  -destination-timeout 60 \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 15 \
  -maximum-test-execution-time-allowance 30 \
  -resultBundlePath "$result_bundle" \
  CODE_SIGNING_ALLOWED=NO
