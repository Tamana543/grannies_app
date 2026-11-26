# Grannies Healthbar

A Flutter Android app for grandmas and the people who care for them. White surfaces, soft green and red panels, illustrated role choices, and animated onboarding.

## Run

Use Flutter 3.47 / Dart 3.13 or newer, JDK 17 or 21, and Android SDK 36. Android 9 (API 28) or newer is required.

```sh
flutter pub get
flutter run
```

The default API is `https://undrdsk0m2.pythonanywhere.com/`. No USB forwarding is needed for this hosted server. The server address is configured at build time:

```sh
flutter run --dart-define=API_BASE_URL=https://your-server.example
```

An address saved by an older version takes precedence over the build default. Fresh installations use the build default.

For local development, build with `--dart-define=API_BASE_URL=http://127.0.0.1:8000` and forward the port over USB or from an emulator:

```sh
adb reverse tcp:8000 tcp:8000
```

Keep your Python server bound to `127.0.0.1:8000` for this local setup.

## Build APK

For smaller APKs to install or share, use:

```sh
bash tool/build_small_apks.sh
```

This creates optimized release APKs in `build/app/outputs/flutter-apk/`, one per CPU architecture. Install only the matching APK: `app-arm64-v8a-release.apk` for most current phones, `app-armeabi-v7a-release.apk` for 32-bit ARM devices, or `app-x86_64-release.apk` for x86 emulators/devices. Splitting avoids bundling all three architectures into each download. Release builds remove debugging overhead, unused code/resources and unused Material icons. Keep `build/symbols` with each release to decode Dart stack traces; rebuilding can replace those files.

For Google Play, build an app bundle so Play delivers the files each device needs:

```sh
flutter build appbundle --release --tree-shake-icons --split-debug-info=build/symbols
```

For development with hot reload:

```sh
flutter build apk --debug
# Output: build/app/outputs/flutter-apk/app-debug.apk
```

The generated release configuration currently uses debug signing. Configure your own upload key before distributing a release through Google Play.

## API contract

This client matches the supplied FastAPI implementation:

- `GET /` returns newest-first rows: `[{"text":"<JSON string>","date":"...","time":"..."}]`.
- `POST /{text}` receives the JSON as one URL-encoded path segment, with no body. It returns the JSON number `200` before its background database write completes. The client verifies the saved plan with subsequent GET requests.

```json
{
  "AB23--XY89": {
    "granmasAge": 74,
    "granmasName": "Rose",
    "childName": "Sam",
    "helperPhone": "8801812345678",
    "Medicenes": {
      "Vitamin D": ["08:00", "20:30"]
    }
  }
}
```

The helper phone number is normalized to Bangladesh international format (for example, `01812345678` becomes `8801812345678`) and stored as `helperPhone` alongside the existing care-plan fields. Older records without a phone number still load. Helpers can add or update their number using the phone icon on their dashboard. The backend spelling is preserved. JSON arrays represent medicine times; each time repeats daily in the device's local timezone. The app limits a plan to 1,000 characters to respect the declared server field size. Because the current server uses a single URL path parameter, slashes in names are rejected.

Plans are saved to private app storage before syncing. Failed saves remain pending locally and retry silently every 30 seconds while the dashboard is active. Grandma's pairing screen polls every 15 seconds; her dashboard refreshes every 30 seconds while active.

## Project structure

- `lib/models/`: care plans and tolerant API record parsing.
- `lib/services/`: private local storage, fixed install code, GET/POST adapter.
- `lib/screens/`: welcome, pairing, helper questionnaire, dashboards.
- `lib/widgets/` and `lib/theme.dart`: shared panels, illustrations, button motion, light theme.
- `android/`: Android host, WhatsApp sharing/fallback, document picker, image crop/resize.
- `test/`: API contract, storage persistence, and widget-flow tests.
- `tool/`: standalone domain checks and direct headless visual smoke check.
- `reports/report.text`: implementation status and important limitations.

## Checks

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
dart run tool/check_domain.dart
```

For a direct headless smoke check in environments where Flutter's test driver cannot open a local socket:

```sh
flutter build bundle --debug --target=tool/visual_smoke.dart
# Replace FLUTTER_SDK with your Flutter SDK directory.
FLUTTER_SDK/bin/cache/artifacts/engine/linux-x64/flutter_tester \
  --run-forever --disable-vm-service --enable-software-rendering \
  --flutter-assets-dir=build/flutter_assets build/flutter_assets/kernel_blob.bin
```

This check exercises both roles and the helper questionnaire, writes screen previews to the system temporary directory, and exits with a nonzero status on failure. Rebuild with the default `lib/main.dart` target before using the app normally.

## Scope

The four-character code persists across restarts and upgrades, but clearing app data or uninstalling removes it. Four characters cannot guarantee global uniqueness; server-side code registration and collision handling are needed. The current server exposes all records without authentication, so use test data until it has authentication, access controls, and HTTPS. Health data is also present in POST URLs with this server design; a future server should accept an authenticated JSON body.

Grandma’s device schedules daily medicine notifications using Android AlarmManager. Enable notification and exact-alarm permissions when prompted (or use the bell icon on her dashboard). Reminders survive app closure and are restored after reboot, app updates, clock changes and timezone changes. Medicines at the same time share one notification. Without exact-alarm access, Android may delay reminders; disabled notifications, force-stop and device battery restrictions can prevent or delay alerts. Times repeat in the device’s local timezone. Dose tracking is not implemented. SOS sends an SMS through bdapps; it does not place a call. Family photos stay on the device, are center-cropped to 16:9, resized to 1280 × 720, and saved as JPEG. No MAC address or broad storage permission is used.

## Build memory and toolchain

The Android build uses Gradle 9.3.1, AGP 9.1.1 and built-in Kotlin with compiler version 2.3.20 (Flutter 3.47+). The Gradle heap is capped at 1536 MB, with one worker and Kotlin compilation in the same process, to reduce memory pressure. The first build downloads the updated tooling and needs internet access.

If a Gradle daemon disappears, check the Linux kernel journal for an out-of-memory kill. Close memory-heavy applications before retrying; changing dependency versions alone does not fix an out-of-memory kill.

## Family SOS and bdapps

The app calls the documented bdapps subscription and SMS APIs directly; the existing care-plan server does not need new endpoints. The helper’s phone number is both the family subscription account and the SMS destination. Grandma’s number is not collected.

Use the gitignored `.local/bdapps.json` file for `BDAPPS_APPLICATION_ID` and `BDAPPS_PASSWORD`. `tool/build_small_apks.sh` includes this file automatically if present. To run locally with these settings:

```sh
flutter run --dart-define-from-file=.local/bdapps.json
```

The first SOS tap checks `/subscription/getStatus`. If not registered, it calls `/subscription/send` with `action: "1"` and checks status again. After confirmed registration, a subsequent tap sends `/sms/send` to the helper with:

> hi [helper], grandma has reached for the S.O.S button. Please call her back.

A successful SMS response means the provider accepted the message, not that the helper received or read it. There is no automatic retry for SMS requests, to avoid duplicate alerts after an uncertain network result. Routine care-plan refreshes remain silent.

New subscriptions are enabled and use the tariff configured for this application in bdapps, as authorized. No direct-debit requests are made; subscription and SMS pricing follow the provisioned application. Direct app integration includes the credentials in the APK, as requested; keep this build private.

API reference: https://dev.bdapps.com/API_Documentation/bdapps_tap_api.html
