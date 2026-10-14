# Developer setup

Implementation-specific commands and platform wiring will be expanded with the
V1 slice. Required prerequisites: stable Flutter with Dart 3, Android Studio/SDK
and Java 17 for Android, Xcode/CocoaPods on macOS for iOS, Firebase CLI, and a
Firebase/Google Cloud project with Maps SDKs enabled.

Use separate development and production Firebase projects. Enable email/password
Authentication, provision Firestore and Storage, and deploy repository rules before
use. Supply client Firebase options via ignored local configuration or dart defines;
never check in API keys, google-services.json, GoogleService-Info.plist, service
account JSON, keystores, key.properties, provisioning profiles, or passwords.
Maps SDK keys must be platform-restricted and injected through local native config.

Emulator testing and dependency/version commands will accompany implementation.
Physical Android/iOS testing is mandatory for permission, GPS, map and persistence
behavior. No credentials are needed for domain or mapping unit tests.
