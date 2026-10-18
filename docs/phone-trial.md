# Install the Android phone trial

The `Android phone trial` GitHub Actions workflow builds an installable debug APK
with `--dart-define=TRIAL_MODE=true`. It needs no Firebase account or Firebase keys.
The workflow now reads the repository Actions secret `GOOGLE_MAPS_ANDROID_KEY`
for Google Maps satellite imagery. See [developer setup](developer-setup.md) for
SDK activation, billing and package/certificate restrictions. Signing credentials
stay outside Git; an optional private debug keystore secret stabilizes trial updates.

1. Open the successful **Android phone trial** run on GitHub Actions.
2. Under **Artifacts**, download **OrchardAtlas-Android-trial** while signed in.
3. Extract the ZIP and transfer `OrchardAtlas-trial.apk` to an Android phone.
4. Open the APK using the phone's Files app. If Android asks, permit that installer
   to install unknown apps, then install it. You may disable that permission again.
5. Launch **OrchardAtlas Trial**. No sign-in is required.

The trial has a separate Android application ID (`com.orchardatlas.orchard_atlas.trial`)
so it does not share app storage with a connected OrchardAtlas installation.
A later debug build may have a different signing key. If Android refuses an update,
keep the installed trial if you need its records. **Uninstalling deletes local records**;
only replace an installation after preserving the data or deciding it is disposable.
The artifact includes `SHA256SUMS.txt` for checking that the transferred APK matches.
Artifacts expire after 14 days; a new branch push builds another trial.

## Trial 0.5: multiple orchards and saved map views

- Open **Orchard options → Select orchard** to create or select an orchard. The last
  selection is remembered on this device. Plants, activities, tasks, areas, rows,
  seasonal crops, harvests and custom taxonomy stay within that orchard.
- **Orchard options → Map settings → Set current view as default** saves location,
  zoom, bearing/tilt and full-screen/data mode for this orchard. Restart to restore
  that view. Different orchards can have different defaults. Preferences are local
  to the device/user; they are not synchronized to other devices.
- Start **Add row / Add area** without losing the map's location or zoom. Use the
  visible **Back to map** arrow to leave drawing; nonempty drafts need confirmation.
  Saving/cancelling restores the preceding display mode. The separate area/row
  editor also receives the map's current camera when opened through the layout list.
- Existing trial records remain in **Trial orchard**. Additional orchards get
  independent snapshots. This storage upgrade does not move or erase old records.
- [Feature backlog](FEATURE_BACKLOG.md) is the ongoing list of planned work.

## Trial 0.4: satellite map, drawing and location search

- **Map** defaults to Google satellite imagery in both trial and connected modes.
  Tiles need internet and a properly configured key. Without a key the app labels
  its coordinate sketch explicitly; data remains accessible.
- Tap **Full screen map** to hide status/filter/tab controls. **Data mode** restores
  them while preserving the camera, selection, filters and any draft drawing.
- Choose **Add row** or **Add area** on the map. Tap along the row or around the
  boundary, drag vertex pins to adjust, or undo. **Finish drawing** collects a name
  and optional parent area/bed. Tap the saved shape for detail, plants and crops.
  Cancel/Back asks before discarding a nonempty draft. Coordinate editing remains
  available under **Orchard options → Areas, beds & rows**.
- The map search button accepts an address or decimal **latitude, longitude**.
  Choose from address results. Coordinate search works without an address service.
  While drawing, search/GPS changes the view without adding a point.
- Download `SIGNING_CERTIFICATE.txt` alongside the APK and allow its SHA-1 for
  `com.orchardatlas.orchard_atlas.trial` in the Android Maps key restrictions.

The following sections describe earlier trial versions; 0.4 replaces their
coordinate-sketch-only map behavior when Google Maps is configured.

## Things to try
- Open **Add Plant** and grant foreground GPS permission. The form fetches your
  location automatically; coordinates can also be entered or corrected manually.
- Select group → genus → species → optional cultivar. Use **Add new option** to
  extend a dropdown and select its icon. The plant name follows selections until
  you customize it. Optionally enter a planting date, check the coordinates, and
  save. Choose **Back to map** to see the tappable plant marker.
- Open the marker or use the **Plants** tab, record care and harvest activities,
  and inspect annual mass/count totals.
- Choose **Add another** after saving, or **Add Another Like This** from detail.
  Verify the taxonomy/name carry over and a fresh GPS position is fetched.
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

### Updated plant entry

Taxonomy dropdowns now allow property-specific additions with a required built-in map symbol. Names follow selections unless customized. Add Plant fetches GPS automatically, offers an optional planting date, and asks whether to add another after each save. An explicit map-selected position takes precedence over automatic GPS. Existing saved trial JSON remains readable; new taxonomy options and planting events persist on the phone.

Android updates must have the same signing certificate as the installed app. The existing trial workflow uses temporary debug signing, so another build may be rejected as an update. If that happens, keep the installed version and its records; uninstalling deletes local trial data. A stable private signing key is required for reliable future in-place updates. No signing credentials are checked into this repository.


## Trial 0.2: management and tasks

- Add a new plant: date defaults to today. Clear it to leave planting unknown. A set date adds one planting activity; no date adds none.
- Add another from the popup or a plant detail: planting date, rootstock and source carry over, including a cleared date. Each save creates a new identity and a planting activity only when dated.
- Enter rootstock, nursery/source and notes. Detail displays metadata and GPS accuracy; manual coordinate changes clear captured accuracy.
- Edit metadata, archive a plant, switch the status filter to archived, then restore it. History and tasks should remain intact.
- Search or filter by classification ancestor, planting year and status; map and list should agree.
- On Tasks, create a whole-property or plant-specific task with optional due date. Complete, cancel or reopen it, filter its status/due window, and verify it survives closing and reopening the app. Due dates do not trigger background notifications.
- Record first/full bloom, petal fall, fruit set, pests/disease or damage. Record lb and kg harvests in the same year and verify the totals remain separate.

Older trial saves load with active status and empty metadata; an existing planting activity supplies a missing planting-date field. No records are intentionally deleted by this storage upgrade. This does not remove the signing limitation described above: replacing an installed trial by uninstalling still deletes its data.

## Trial 0.3: group checklists, layout and seasons

The launcher uses the supplied **OrchardAtlas Original Option 1** artwork on Android and iOS. Android's flattened source is used as a legacy launcher image, not an invented adaptive foreground.

1. Open **Areas, beds & rows** from the home app-bar icon. Add an area/bed polygon or row line. Tap vertices in order, undo, enter coordinates, or edit a numbered vertex. GPS centers the sketch; it does not claim survey accuracy. Areas close automatically. The trial sketch has no basemap; connected mode uses Google Maps.
2. Create a garlic bed, then **Add child area / row** twice. Name the rows. Section detail shows children, assigned plants, current crops and previous seasons. Shape/name/notes can be edited; parent identity remains fixed.
3. Use **Add plant here**, or choose an area/row on Add/Edit Plant. Put several blueberry bushes of different varieties in one row. Similar entry preserves the section, planting date and rootstock/source. Home plant filters can select an area and all its descendant rows.
4. For a raspberry patch or garlic row, choose **Add seasonal planting**. Select the species/variety, add a new variety if needed, and enter a season/year and optional planting date. Label a mixed row segment, such as north half. Permanent sections can contain several varieties or seasonal records without individual plant markers.
5. Record crop harvests with explicit units and dates. **Mark harvest complete** or **End season** preserves the record. **Replant for a new season** creates another UUID record with classification/label prefilled and a fresh season/date; edit those fields before saving. Prior crop varieties, dates and unit-separated yearly harvests remain available. Due-date tasks can target sections or crops.
6. Add a task and select **Group: all matching plants**. Choose Apple (includes varieties), and optionally an area/row (includes descendants). One submission creates a checklist for the matching active plants. Alternatively choose a group of areas/beds/rows or seasonal crops; selecting a garlic bed and row targets produces one checklist member per row. Open the group and complete, skip/cancel or reopen each plant independently. Completion dates and remaining work persist. Counts use the whole group even when the main list is filtered. Membership is captured at creation; later-added trees are not silently included. Maximum 400 members per group; split larger groups by area. Checking a task does not automatically create a pruning activity; tap the plant to record that separately.

All additions use the trial's existing local storage and write queue. Existing plants, tasks and activities load with unassigned sections/no group IDs and empty layout/season collections. The debug signing limitation still applies: do not uninstall an old trial with valuable local records merely to resolve a certificate mismatch.

## Map-based plant location editing

Open a plant, choose **Edit**, then **Pick location on map**. The satellite map
starts at the editor's current coordinates (or the saved plant position if the
manual coordinates are invalid). Tap a new spot or drag the pin, then choose
**Use this location**. Review any other edits and choose **Save changes** to persist
the new position offline. Until saved, the plant's stored position is unchanged.
**Cancel** or Back discards the picker selection; leaving the editor without saving
discards confirmed draft changes too. Reopening the picker uses the editor's draft.

Moving a plant preserves its identity, history, classification and Area/Row
assignment, including row order. A changed position clears the old GPS accuracy
claim. Plants assigned to an Area/Row remain hidden as individual map markers.
Without a configured Google Maps key, the existing coordinate sketch supports
tapping a location; manual latitude/longitude fields remain available. Satellite
tiles require connectivity unless already cached; saving a position remains local.
