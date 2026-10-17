# Drive backup, retention and update-safe Android builds

The Android local trial supports the system document picker. Install/sign in to
Google Drive, choose **Backup & restore → Set up Drive backup**, select Drive in
the picker's navigation drawer, and choose a private folder. No Drive API key,
OAuth client ID or Google account token is embedded in the app. Other compatible
document providers also work. This is file backup, not live multi-device sync.

All local orchard snapshots, custom taxonomy, plants, sections, crops, harvests,
activity and task histories, recurrence definitions, orchard selection, map defaults
and task sort preferences are included. Firebase credentials, authentication data,
file-access grants and backup connection settings are excluded. Connected Firebase
records and photo binaries are not part of this Android trial format.

Changes trigger a debounced write while the app runs; opening the app retries the
latest snapshot. **Back up now** explicitly writes before leaving. Status records a
successful provider write, not proof that Drive has uploaded its local cache. Check
Drive's upload status before uninstalling. Failed writes remain visible and are
retried after another change or restart. There is no background upload guarantee.
The app updates the selected file; keep independent copies for version history.
A provider interruption during replacement can leave an incomplete file; malformed
backups are rejected on restore, so verify a backup and keep another copy before
removing local records.

## Uninstall and restore

Android cannot run application code or show an app-owned prompt during uninstall.
It removes internal app storage and URI permissions. Files created in Drive or
another external document provider remain independent of the app.

**Retain backup when preparing to uninstall** defaults on. **Prepare to uninstall**
first writes the latest snapshot. Turning retention off does not silently remove
files: that action asks for explicit confirmation before deleting the selected
backup. Other copies remain. Uninstalling directly through Android always leaves
external copies alone. After reinstall, choose **Restore from Drive or a backup
file**, approve replacing phone data, and select the JSON backup. Re-select a new
backup write target afterward; old write permissions are not restored.

Restore validates every orchard snapshot before changing device records. A local
recovery snapshot is retained. A pending restore journal is completed at startup if
the process stops midway. Local copies and that journal are lost on uninstall;
external backups must already be saved. Backups contain sensitive orchard locations
and notes as readable JSON; use a private folder and protect copied files.

## One-time stable signing setup

Future downloadable builds require the same private signing key. Random runner
keys are no longer published. A missing signing secret still permits CI compile
checks but skips the downloadable APK and emits a setup warning.

1. On your computer install a JDK (for `keytool`) and Python 3.
2. From this repository run:

   ```sh
   python3 scripts/create-trial-signing.py --directory "$HOME/OrchardAtlas-private-signing"
   ```

3. Open GitHub → **akjeffrey/OrchardAtlas → Settings → Secrets and variables →
   Actions → New repository secret**.
4. Name it **ANDROID_TRIAL_DEBUG_KEYSTORE_BASE64**. Paste the contents of the
   generated `orchardatlas.signing-secret.txt` file as its value. Do not paste it
   into an issue, PR, chat or log. Keep the original keystore privately backed up.
5. Run **Actions → Android phone trial → Run workflow → main**.
6. Download the trial artifact and install its APK over the existing app when the
   signing certificate matches. Keep application ID
   `com.orchardatlas.orchard_atlas.trial` and this key for every subsequent trial.

The helper creates the Android debug alias `androiddebugkey` with the debug
passwords expected by Gradle. This is a private trial signer, not Play production
signing. GOOGLE_MAPS_ANDROID_KEY remains required. Add the new signing certificate's
SHA-1 to the Google Maps key's Android application restrictions for the trial ID;
the downloadable artifact includes SIGNING_CERTIFICATE.txt.

### Moving an existing temporary-key installation

An old randomly signed APK cannot be upgraded with a different key. Android will
reject the update; it cannot safely be bypassed. If the original private key is
available, use it instead of generating a new one.

Before uninstalling an old trial that has no export screen, use a computer with
Android Platform Tools, USB debugging enabled and the phone authorized:

```sh
python3 scripts/backup-installed-trial.py OrchardAtlas-backup-migration.json
```

This reads only the debug trial's orchard-related preferences via `adb run-as`.
It does not read Google/Firebase credentials. If it fails, **do not uninstall**.
Copy the resulting private JSON to Drive and keep a second copy. Only after
verifying the backup exists, uninstall the old app, install the permanent-key
build, restore the JSON, and verify all orchards before deleting any copies.
This computer-assisted migration is needed only when the old signer cannot be reused.

## Version policy

Downloadable Android builds use SemVer **0.N.0+N**, where N is the existing
**Android phone trial** workflow's `github.run_number`. The history had 23 runs when
this increment started, so the next build is 0.24.0 (24). Feature and main runs
share the counter; failed/compile-only runs consume numbers. Re-running an attempt
keeps that build's identity; dispatch a new run for a new version. Diagnostic native
builds in Foundation checks are not extra distributable app versions.

The first component stays zero during development, the minor component increases
for each trial build, and patch stays zero. The Android versionCode increases too,
allowing in-place updates. The app's Backup & restore screen shows the actual
installed version; the artifact includes VERSION.txt. pubspec.yaml is the local
build fallback. Do not recreate the workflow/counter or lower versionCode.

Physical-phone acceptance: Drive picker/grants, offline failure and retry, full
multi-orchard restore after reinstall, interrupted restore, retention/deletion,
Google Maps restrictions with the stable signer, and installing two sequential
stable-key APKs while preserving data. iOS file backup is not implemented here.
