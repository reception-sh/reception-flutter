#!/bin/sh
# Compiles the iOS host's pure-logic files with their tests under strict concurrency and runs them:
# on macOS for Foundation-only logic, in an iOS simulator for UIKit logic.
# Usage: tool/test_native.sh [simulator udid or name, default: booted]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
sources="$root/ios/reception_flutter/Sources/reception_flutter"
tests="$root/tool/native_tests"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
flags="-swift-version 5 -strict-concurrency=complete -warnings-as-errors -parse-as-library"

# shellcheck disable=SC2086
xcrun swiftc $flags \
  "$sources/PushToken.swift" "$sources/NotificationRouting.swift" "$sources/OnceCompletion.swift" \
  "$sources/PaywallRequests.swift" "$tests/LogicTests.swift" -o "$scratch/logic-tests"
"$scratch/logic-tests"

case "$(uname -m)" in arm64) arch=arm64 ;; *) arch=x86_64 ;; esac
# shellcheck disable=SC2086
xcrun --sdk iphonesimulator swiftc $flags -target "$arch-apple-ios17.0-simulator" \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  "$sources/ReceptionColor.swift" "$tests/ReceptionColorTests.swift" -o "$scratch/color-tests"
xcrun simctl spawn "${1:-booted}" "$scratch/color-tests"
