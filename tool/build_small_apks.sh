#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

# Ship one CPU architecture per APK and keep Dart debugging symbols off-device.
# Flutter also enables release code/resource shrinking and icon tree shaking.
bdapps_args=()
if [[ -f .local/bdapps.json ]]; then
  bdapps_args+=(--dart-define-from-file=.local/bdapps.json)
fi
flutter build apk --release --split-per-abi --tree-shake-icons \
  --split-debug-info=build/symbols "${bdapps_args[@]}"

printf '\nInstall only the APK matching the device CPU (usually arm64-v8a).\n'
ls -lh build/app/outputs/flutter-apk/app-*-release.apk
printf '\nKeep build/symbols with this release to decode Dart stack traces.\n'
