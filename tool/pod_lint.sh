#!/bin/sh
# Lints ios/reception_flutter.podspec in both CocoaPods modes (--use-modular-headers, --use-libraries).
# CocoaPods Trunk's Flutter pod predates the scene lifecycle API, so the lint builds against a lint-only Flutter
# podspec that vendors the installed Flutter SDK's engine (derived from `which flutter`).
# The plugin podspec uses `:path` as its source like every Flutter plugin, which pod lib lint always reports as a
# warning. If that warning makes the lint fail, the lint is repeated with --allow-warnings and all warnings are
# printed for review; any other warning or error fails the script.
set -eu
# CocoaPods needs a UTF-8 locale; non-interactive shells often have none.
export LANG="${LANG:-en_US.UTF-8}"
root=$(cd "$(dirname "$0")/.." && pwd)
flutter_root=$(dirname "$(dirname "$(readlink -f "$(which flutter)")")")
engine="$flutter_root/bin/cache/artifacts/engine/ios/Flutter.xcframework"
[ -d "$engine" ] || { echo "Flutter engine not found at $engine; run 'flutter precache --ios'." >&2; exit 1; }
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
ln -s "$engine" "$scratch/Flutter.xcframework"
cat > "$scratch/Flutter.podspec" <<SPEC
Pod::Spec.new do |s|
  s.name = 'Flutter'
  s.version = '1.0.0'
  s.summary = 'Flutter engine from the local Flutter SDK, for linting only.'
  s.homepage = 'https://flutter.dev'
  s.license = { :type => 'BSD' }
  s.author = 'Flutter Dev Team'
  s.source = { :http => 'https://flutter.dev' }
  s.ios.deployment_target = '17.0'
  s.vendored_frameworks = 'Flutter.xcframework'
end
SPEC
cd "$root"
for mode in --use-modular-headers --use-libraries; do
  echo "== pod lib lint $mode"
  if pod lib lint ios/reception_flutter.podspec --skip-tests "$mode" --include-podspecs="$scratch/Flutter.podspec" \
    >"$scratch/lint.log" 2>&1; then
    echo "passed without warnings"
    continue
  fi
  issues=$(grep -E '^ *- (WARN|ERROR) ' "$scratch/lint.log" || true)
  if [ -z "$issues" ] || echo "$issues" | grep -qv 'Missing primary key for `source` attribute'; then
    cat "$scratch/lint.log"
    exit 1
  fi
  if ! pod lib lint ios/reception_flutter.podspec --skip-tests "$mode" --include-podspecs="$scratch/Flutter.podspec" \
    --allow-warnings >"$scratch/lint.log" 2>&1; then
    cat "$scratch/lint.log"
    exit 1
  fi
  echo "passed with --allow-warnings; warnings:"
  echo "$issues" | sort -u
done
