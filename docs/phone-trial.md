# Install the Android phone trial

The `Android phone trial` GitHub Actions workflow builds an installable debug APK
with `--dart-define=TRIAL_MODE=true`. It needs no Firebase account, project keys,
Maps key, or production signing credential. The workflow generates the standard
Android debug signing key on its runner; signing keys are not stored in Git.

1. Open the successful **Android phone trial** run on GitHub Actions.
2. Under **Artifacts**, download **OrchardAtlas-Android-trial** while signed in.
3. Extract the ZIP and transfer `OrchardAtlas-trial.apk` to an Android phone.
4. Open the APK using the phone's Files app. If Android asks, permit that installer
   to install unknown apps, then install it. You may disable that permission again.
5. Launch **OrchardAtlas Trial**. No sign-in is required.

The trial has a separate Android application ID (`com.orchardatlas.orchard_atlas.trial`)
so it does not share app storage with a connected OrchardAtlas installation.
A later debug build may have a different signing key; if Android refuses an update,
uninstall the previous trial first. **Uninstalling deletes its local records.**
The artifact includes `SHA256SUMS.txt` for checking that the transferred APK matches.
Artifacts expire after 14 days; a new branch push builds another trial.

## Things to try
- Tap **Current GPS location** and grant foreground location permission, or use
  **Add Plant** to enter known coordinates manually.
- Select group → genus → species → optional cultivar, name the plant, confirm its
  position and save it. The coordinate preview shows a tappable plant marker.
- Open the marker or use the **Plants** tab, record care and harvest activities,
  and inspect annual mass/count totals.
- Use **Add Another Like This**; verify it requires a new confirmed position.
- Wait for **Saved on this phone**, close/reopen the app and verify your records.
  Airplane mode does not prevent local recording; GPS still depends on signal.

## Trial limits
The app clearly labels this mode as PHONE TRIAL. It uses a local coordinate sketch,
not Google Maps tiles or satellite imagery; verify coordinates before recording
real plants. No cloud synchronization, account sharing, photo upload or backup is
provided in trial mode. Data is stored only on the device, and uninstalling or
using **Sign out and clear cached records** deletes it. These trial records do not
migrate automatically into a Firebase project. This mode does not validate native
Firestore offline persistence or connected Google Maps behavior.

The connected build remains the default when `TRIAL_MODE` is omitted; its Firebase,
Maps and security-rule setup is unchanged. See [developer setup](developer-setup.md).
An iPhone install requires a separate iOS device build and Apple signing/provisioning;
the Android APK cannot be installed on iPhone. CI simulator builds are not iPhone
installation packages.
