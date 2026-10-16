# Foundation validation

Toolchain: Flutter 3.47.7 stable, Dart 3.13.5, Node 24.19.0, Java 21.
CI pins Flutter 3.47.7 and uses Node 22/Java 21.

## Automated results
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 16 tests covering domain validation, annual mass/count
  totals, calendar dates, taxonomy, UTC Firestore round trips, repository streams,
  write rejection, bulk entry, parent-selector reset, pending-state rendering,
  and confirmed save navigation to a map camera target.
- `flutter build bundle --debug --no-pub --target-platform=android-arm64`: Dart app
  bundle compilation. This is not an APK/native platform build.
- Firestore emulator suite: 6 tests passed. Covers owner/anonymous/stranger
  authorization, private queries, immutable events, harvest validation, author
  forgery, malformed item changes, reserved paths, and missing parent items.
- Dart formatting and `git diff --check` pass. Domain/UI have no Firebase imports.
  Reviewed staged files and scanned for common key/token/private-key patterns;
  no credentials or local project configuration are included.

## Remaining release checks
This environment has no Android SDK/device or macOS/Xcode. No real Firebase/Maps
project keys were provided or used. Android/iOS native builds, GPS permission flows,
map rendering, foreground accuracy, offline force-stop/restart durability, reconnect
sync, cross-device data and cache-clearing sign-out must be tested with developer
configuration using [setup](developer-setup.md) and the
[offline acceptance scenario](offline-first.md). Fake Firestore does not simulate
native persistent disk cache; pending-state widget tests use injected snapshots.

## Known scope limits
- Small curated taxonomy catalog, one private default property, managed-plant UI.
  Concurrent first-time setup on multiple devices can create multiple properties;
  use one device during initial V1 setup. Multi-property choice is deferred.
- Sharing, tasks, foraging-resource screens, photo capture/upload and activity
  corrections are future slices. Storage remains closed under V1 rules.
- Map tiles are not guaranteed offline. Cached list/detail data can be incomplete.
- Rejected-write warnings are observed during the process lifetime, not persisted
  as a custom recovery journal. Server rejection can roll back a local record.
- Sign-out clears the cache and requires app restart; pending changes can be lost,
  so the UI prompts the user to wait for sync before signing out.

## Follow-up review of PR #1

The initial GitHub Actions run passed both the Flutter and Firestore security jobs:
[Foundation checks](https://github.com/akjeffrey/OrchardAtlas/actions/runs/38794845308).
Those results apply to the initial foundation commit, not the follow-up fixes.

The follow-up fixes cache-first property loading, captures provider dependencies
before asynchronous waits, centers a delayed native map on the latest GPS selection,
and lets the GoogleMap widget own controller disposal. Five regression cases were
added for offline lookup/error behavior and map lifecycle. They have **not been
executed**: the user requested that testing be skipped. The review commit originally used `[skip ci]`. The subsequent request to run CI
and publish a phone trial starts GitHub Actions on the updated branch. Native
Android and iOS simulator build results should be checked on that current commit.

No Firebase/Maps developer configuration or physical devices are available in this
workspace. Setup is waiting for the developer project ID and secure configuration.
Native/device acceptance checks remain outstanding; this review does not constitute
release or merge approval.

## Android phone-trial build

A separate, explicitly labeled `TRIAL_MODE` configuration uses device-local storage
and a coordinate preview without Firebase/Maps keys. Its CI workflow uploads a signed
debug APK and SHA-256 checksum as **OrchardAtlas-Android-trial**. See
[phone-trial instructions](phone-trial.md) for installation, data-loss limitations,
and the distinction from the connected app. Local test execution remains skipped;
CI and phone installation results must be checked separately.


## Plant-entry feedback validation (2026-10-16)

CI on `fc97c5e` passes formatting/static analysis, all 25 Flutter tests and all 8 Firestore rules tests: [Foundation checks](https://github.com/akjeffrey/OrchardAtlas/actions/runs/38921810584). This supersedes the earlier test counts and skipped-test notes above. Coverage includes selection-driven names and custom-name preservation, creating a taxonomy option with an icon, fresh GPS for bulk entry, the post-save dialog and map navigation, custom taxonomy mapping, backwards-compatible trial saves, dated planting persistence across repository restart, and atomic Firestore plant/planting-event authorization. Native builds and the refreshed APK are tracked in GitHub Actions; physical-phone acceptance remains a manual check.
