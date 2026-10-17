# Trial 0.6 — requested backlog

This release implements the user-added backlog after Trial 0.5. The original
deferred product features remain unchecked in FEATURE_BACKLOG.md.

## Try on a phone

Use the Android APK from the Phone trial workflow for this release. Install over
the existing trial without uninstalling to preserve local records. The Maps key
continues to come from the GOOGLE_MAPS_ANDROID_KEY GitHub Actions secret.

- Rename the orchard using the orchard selector. Fresh installations start at Home Orchard.
- Add an Area or Row from the map. Choose a color and optional central icon.
  The Areas & Rows page also uses satellite imagery.
- Row vertices define direction: first is Start, last is Finish. Plants default
  to the row's start location and append in row order. Use the row plant list's
  up/down buttons to rearrange them. Area plants default to the shape center.
- Plants assigned to sections have no individual map marker. A classification
  filter hides sections without active matching plants, including nested rows.
- Classification entry uses Group, Type, Variety. Existing cultivar IDs stay
  valid and appear as Variety choices under the appropriate Type.
- Edit all plant fields. Archive hides a plant from the map; Archived Plants is
  a list with edit/unarchive actions. Permanent deletion requires confirmation.
- Create a matching task with zero or many matching plants. Matching plants
  added later receive assignments automatically. Select daily, weekly, monthly
  or yearly repetition; open a group checklist to switch occurrence/history.
- Optionally link a plant activity to a task. Complete a member, inspect the
  generated activity, then reopen: only its linked activity is removed. Deleting
  a generated activity also reopens that member. Edit activities to correct
  dates/quantities/units; yearly totals are recalculated.
- Filter tasks/activities, change task sort, restart, and check the sort persists.
  Default order is undated, next due ascending, then overdue ascending.
- Open Group / Type / Variety to see matching plants, tasks, activities and
  harvest totals separated by unit.

## Persistence, security and limitations

Local trial changes, recurrence definitions, occurrence history and ordering are
stored offline in each orchard's existing JSON snapshot. Existing beds are read
as Areas without changing identity or user-entered names. Legacy taxonomy and
snapshot task records remain readable. Recurrence advances on opening the app
and while it is active; background notifications are deferred.

Deploy the updated firestore.rules and storage.rules before using this version
with a connected Firebase project. Owner-only rules now permit full plant edits,
activity correction/deletion, task plans and permanent deletion. UUID5 identifiers
make generated task assignments and linked events stable. No sharing is enabled.

Cloud permanent deletion requires an online server inventory and may need retry
if interrupted. The repository deletes descendants, referenced task records,
activity/photo metadata and known owner-scoped Storage files before parent records.
It cannot discover unreferenced Storage objects, and does not provide a multi-device
transaction or background retry worker. Avoid concurrent edits during deletion.
The local trial cascade works offline. Normal connected edits still use Firestore
persistence. Google imagery itself requires connectivity.

Android requests immersive display with transient system-bar reveal; actual
behavior depends on Android version and navigation mode. Physical-device checks
remain necessary for navigation gestures, imagery, offline restart and GPS.
