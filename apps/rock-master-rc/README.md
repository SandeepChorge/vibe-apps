# Rock Master RC

Offline Bluetooth Low Energy controller for the Wonder Toys Rock Master
(and other LCW_RCcar / TXM-protocol) cars. One Flutter codebase for
Android and iOS. No accounts, no internet, no tracking.

Package `com.rockmaster.rock_master_rc`, version **1.0.4+5**. The longer
write-up (how the car's radios work, the command bytes, and version history)
is in [docs/SUMMARY.md](docs/SUMMARY.md).

## Features

- Scans for nearby BLE devices and also lists phones that are already paired or connected (a connected car stops advertising). Highlights `YC_CAR_DEMO`. On Android 11 and older, asks you to turn Location services on when they are off, because those Android versions otherwise return an empty scan.
- Connects, subscribes to replies, and sends a 10-byte command about every 100 ms. Letting go, disconnecting, or leaving the app sends stop.
- Buttons, joystick, or dual sticks (throttle and steering).
- Editable layouts: swap sides or reorder the button columns, then lock. The layout is saved per mode.
- Speed slider, lights, and vehicle type (Car, Dump truck, Excavator).
- Debug panel with the connected IDs, the last frame, write-with-response vs without, and a BLE inspector. The inspector lists every service and characteristic (UUID and read / write / writeNoResp / notify / indicate), highlights Battery Service `180F` and Battery Level `2A19`, reads every readable characteristic, and logs notify/indicate packets without stopping the 100 ms drive loop.

## Protocol

10-byte frame written to the car's BLE characteristic:

```
AA 00 02 00 00 00 00  [CTRL]  [AUX]  [FLAG]
```

CTRL, MSB first: light, playMode (`10`), spray, right, left, back, forward.
Idle/stop is `0x40`. AUX is speed 30–100 (default 100). FLAG is `01` / `02` / `03`
(Car / Dump truck / Excavator). Default flag is `01`.

UUIDs are discovered at runtime: prefer a primary service with exactly one
notify characteristic and one write characteristic (FFE0/FFF0-style first),
then fall back to any writable characteristic. See [docs/SUMMARY.md](docs/SUMMARY.md)
for the service IDs and example frames.

The official app subscribes to `FFF1` and ignores the bytes. This app still
sends drive frames every 100 ms, and the debug screen's BLE inspector also
subscribes to every notify/indicate characteristic and keeps a timestamped
log (newest first, about 500 entries) with a per-characteristic count and a
changed-bytes hint. Open **Debug** after connecting, then screenshot the
battery callout, the service list (after **Read all readable**), and the
notification log.

## Build locally

Flutter **3.50.0** stable (Dart 3.14, the SDK recorded in `.metadata`).
Android builds need the Android SDK. iOS builds need a Mac with Xcode.

```bash
cd apps/rock-master-rc
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build apk --release --split-per-abi
```

APKs are written to `build/app/outputs/flutter-apk/`. The release APK's
`minSdk` is 24 (`targetSdk` follows the Flutter SDK, `compileSdk` is 37).
`permission_handler_android` requires 24. BLE permissions in the manifest
still include the legacy Bluetooth and location entries for API 21–30.

Without a release keystore, the release APK is signed with the Android debug
keystore, which is enough for sideloading onto a device that does not already
have the app installed under a different certificate.

### Signing a local release

Create `android/key.properties` (gitignored):

```properties
storePassword=<keystore-password>
keyPassword=<key-password>
keyAlias=<key-alias>
storeFile=upload-keystore.jks
```

`storeFile` is resolved from `android/app/` (so the example above means
`android/app/upload-keystore.jks`), or it can be an absolute path. The same
values can be passed as environment variables instead of `key.properties`:

| `key.properties` | Environment variable |
| --- | --- |
| `storeFile` | `ANDROID_KEYSTORE_PATH` |
| `storePassword` | `ANDROID_KEYSTORE_PASSWORD` |
| `keyAlias` | `ANDROID_KEY_ALIAS` |
| `keyPassword` | `ANDROID_KEY_PASSWORD` |

`key.properties` wins when a value is set in both places. If neither source
is complete, release builds fall back to the debug keystore.

The APK that is already installed on the car phone was signed with an Android
debug keystore. Android will only replace that install in place when the new
APK is signed with the **same** keystore. The alias and passwords of a debug
keystore are fixed; the certificate is not. Use the original
`~/.android/debug.keystore` from the machine that produced the installed APK,
not a debug keystore generated somewhere else.

- Alias: `androiddebugkey`
- Keystore password: `android`
- Key password: `android`

## GitHub Actions

Workflow: [Rock Master RC APK](../../.github/workflows/rock-master-rc-apk.yml).

It runs on:

- **Actions → Rock Master RC APK → Run workflow.** Choose `release` or `debug`, and whether to also create a GitHub Release.
- A push to `main` that changes `apps/rock-master-rc/**` or this workflow file. Other apps in the monorepo do not trigger it.
- A tag whose name matches `rock-master-rc-v*` (for example `rock-master-rc-v1.0.4`). Tag pushes publish a GitHub Release with the APKs attached. GitHub does not apply path filters to tags, so the tag pattern is what keeps other apps' tags from starting this build.

Each run executes `flutter pub get`, `flutter analyze`, and `flutter test`, then builds a universal APK and split-per-ABI APKs. Artifacts are uploaded on the run page, named with the version from `pubspec.yaml`. The job summary lists each APK and its size, and says whether the release keystore was used.

Pushes to `main` build a release APK and upload artifacts only. They do not create a GitHub Release.

### Signing secrets

In the GitHub repo: **Settings → Secrets and variables → Actions → New repository secret.** Add all four, or none. If any are missing, the workflow still builds and signs with the debug keystore, and the job summary says so.

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the keystore file, one line |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

Encode the keystore:

```bash
# Linux
base64 -w 0 ~/.android/debug.keystore

# macOS
base64 -i ~/.android/debug.keystore | tr -d '\n'
```

Paste the output into `ANDROID_KEYSTORE_BASE64`. To update the already-installed
debug-signed APK in place, encode that same debug keystore and set the alias to
`androiddebugkey` and both passwords to `android`.
