# Developer setup

## Toolchain
Install stable Flutter (this foundation was validated with the version recorded in
[validation](validation.md)), Android Studio/SDK and Java 17+ for Android, or Xcode
on macOS for iOS. The generated project uses Flutter's current native templates
including Swift Package Manager; let Flutter resolve the plugins. Minimum Android
API is 23 and iOS is 15. Run `flutter doctor` and resolve platform prerequisites.

```sh
flutter pub get
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test
```

Commit `pubspec.lock` for reproducible app dependencies. Domain/mapping/widget tests
need no Firebase project, Maps key or native simulator. Fake-Firestore repository
tests verify mapping and error propagation; they do not prove native disk durability.

## Firebase configuration (local only)
Create a development Firebase project, register Android application
`com.orchardatlas.orchard_atlas` and iOS bundle `com.orchardatlas.orchardAtlas`, enable
email/password Authentication, and provision Firestore and Storage. Deploy rules
before using the app:

```sh
firebase deploy --project YOUR_PROJECT_ID --only firestore:rules,firestore:indexes,storage
```

Create ignored `config/android.json` and `config/ios.json`, each with string values
copied from that platform's Firebase app settings:

```text
FIREBASE_PROJECT_ID
FIREBASE_API_KEY
FIREBASE_APP_ID
FIREBASE_MESSAGING_SENDER_ID
FIREBASE_STORAGE_BUCKET
```

These are JSON objects, for example `{ "FIREBASE_PROJECT_ID": "your-project", ... }`
with every listed key populated. Use the platform-specific Firebase app ID and API
key. App initialization uses explicit FirebaseOptions, so google-services.json and
GoogleService-Info.plist are not required for this email/password slice. If later
plugins require those native files, keep them ignored. Never include service-account
JSON in the app. Registration first use needs network; returning sessions can work
offline. A setup screen appears if config is missing or initialization fails.

## Google Maps and GPS
Enable **Maps SDK for Android** and **Maps SDK for iOS** in your Google Cloud project;
configure billing and restrict separate keys to platform package/signature or bundle.

Android: append `MAPS_API_KEY=your_local_key` to ignored `android/local.properties`.
Keep the SDK/Flutter paths Flutter writes there. The Gradle manifest placeholder
injects the key. Manifest includes Internet and foreground coarse/fine location.

CI reads the repository Actions secret **GOOGLE_MAPS_ANDROID_KEY** and supplies
it to Gradle as `GOOGLE_MAPS_ANDROID_API_KEY`. Keep the value out of Git and logs.
The trial package is `com.orchardatlas.orchard_atlas.trial`, so restrict the trial
key to that package and its signing-certificate SHA-1. The phone artifact includes
`SIGNING_CERTIFICATE.txt` with public certificate fingerprints. Enable Maps SDK
for Android and billing; no Places or Google Geocoding API is used. Address lookup
uses Android Geocoder / iOS CLGeocoder and may require an internet connection.

The same native Maps configuration now enables satellite imagery in the local
trial as well as connected mode. With no key the app labels its offline coordinate
sketch explicitly. A configured key is not proof that billing, SDK activation or
package/certificate restrictions are correct; verify satellite tiles on a device.

For repeatable trial updates, optionally store a standard Android debug keystore
as Actions secret `ANDROID_TRIAL_DEBUG_KEYSTORE_BASE64`. It must use alias
`androiddebugkey`, store/key passwords `android`, and remain private outside Git.
Base64 is encoding, not encryption: only put it in the secrets UI. Generate a
dedicated trial key locally with Java's keytool (do not use production signing):

```sh
keytool -genkeypair -keystore orchard-trial-debug.keystore -alias androiddebugkey \
  -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=OrchardAtlas Trial"
keytool -list -v -keystore orchard-trial-debug.keystore -storepass android
```

Encode that file with your OS's base64 tool and save the result as the keystore
secret. This keeps the signing fingerprint stable across Actions runners. Without
it, each runner generates its own debug key; allow that run's fingerprint in the
Maps key restrictions before trying the APK. Never solve a certificate mismatch
by uninstalling a phone trial containing records you need to keep.

Android emulator Firebase endpoints use HTTP. For development only, add
`android:usesCleartextTraffic="true"` to the application in the debug manifest;
do not enable this in the production manifest. Android's emulator uses host
`10.0.2.2`; iOS Simulator uses `127.0.0.1`.

iOS: create ignored `ios/Flutter/Maps.local.xcconfig`:

```text
MAPS_API_KEY = your_local_key
```

Both Debug and Release xcconfig include it, Info.plist passes the key to AppDelegate,
and AppDelegate initializes Google Maps. Foreground location purpose is declared.
Do not add background location entitlement. Choose your own Apple development team
locally; no signing configuration is committed. No production signing key or
Android release debug signing is included. Profile and release builds need local
Maps config, appropriate Firebase options and your own signing setup.

```sh
flutter run --dart-define-from-file=config/android.json
# On macOS with an iOS device/simulator:
flutter run --dart-define-from-file=config/ios.json
```

Run the acceptance scenario in [offline-first](offline-first.md) on both platforms.
GPS accuracy is shown; manually adjust and confirm before saving. The map's default
world view is not a proposed plant location. A plant list supports tile outages.

## Emulator authorization tests
Install Node 22+ and Java 21, then from the repository root:

```sh
npm ci --prefix security-test
security-test/node_modules/.bin/firebase emulators:exec --project demo-orchard-atlas --only firestore "npm --prefix security-test test"
```

The demo project runs locally without production credentials. To run the mobile
app against emulators, start auth/firestore/storage with the same project and use
local Firebase defines for a registered test app plus
`--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2` (Android) or `127.0.0.1` (iOS).
For iOS simulator HTTP local endpoints, configure local networking ATS exceptions
in a development configuration as needed; do not ship broad ATS exemptions.

## Cache, sign-out and limits
On sign-out, screens unmount and the native Firestore instance is terminated and
its persistence cleared. Restart the app to initialize a fresh instance before
another account signs in. If clearing fails the app stays blocked; retry sign-out
on restart. Sign out only after pending writes sync, otherwise clearing the local
cache can discard them. Local default-property preferences contain only non-secret
IDs scoped by UID. Reinstallation/new device requires network to discover property.

No API keys, Firebase configuration, credentials, password/token logs, keystores,
provisioning profiles, or service accounts belong in Git. The ignore list covers
common local files; review `git diff --cached` before each commit. Configuration is
injected into builds and never printed. Production keys should have platform
restrictions, quotas, and separate debug/release projects.

## Multiple orchards and map preferences

The orchard selector queries properties by authenticated ownerId. Each orchard's
records remain in its existing property subcollections, so no security rule or
Firestore schema migration is needed. Existing records keep their property ID.
Selection is persisted per user on the device; cached orchards remain selectable
offline. Creating another orchard submits its metadata to Firestore's local queue.

The local trial retains the original JSON snapshot for Trial orchard, plus a local
catalog and one independent snapshot per additional UUID orchard. The fixed trial
identity represents this phone, not a cloud account. Default map views are stored
through MapViewRepository and scoped by user ID and orchard ID. No Maps API key or
Firebase credentials are part of these preferences. Physical-device offline restart
and cloud reconnect acceptance checks still apply.

## Trial 0.6 schema and rules

Deploy both updated rule files before using the connected app. This release adds
`taskPlans`, UUID5 generated assignments/events, editable activities, section style
fields and owner-only permanent deletion. Legacy beds read as Areas and legacy
cultivars appear under Variety; IDs and ownership do not change. See
[release-0.6.md](release-0.6.md) for recurrence, deletion and phone acceptance steps.
