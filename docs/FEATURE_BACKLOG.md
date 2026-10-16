# OrchardAtlas feature backlog

Keep this file current in each feature PR. `[ ]` is planned, `[~]` is in progress,
and `[x]` is implemented. Implementation does not replace physical-device checks.

## Current increment

- [x] Multiple user-owned orchards: create/select, remember selection, isolate all records.
- [x] Per-orchard default map view: save current location, zoom and display mode; restore on restart.
- [x] Clear return-to-main control during row/area drawing, with draft-discard confirmation.
- [x] Retain camera location, zoom, bearing and tilt when starting drawing or opening the section editor.

## Implemented foundations

- [x] Google satellite map, GPS positioning, address and decimal-coordinate search.
- [x] Full-screen/data map modes and plant filters/list.
- [x] Plant entry, hierarchical custom taxonomy/icons, automatic names and similar-plant bulk entry.
- [x] Optional planting date defaulting to today/inheriting from similar plant, with planting activity.
- [x] Plant edit/archive/restore, activity history and yearly harvest totals separated by unit.
- [x] Individual tasks and group checklists with completion tracked per plant, row or crop.
- [x] Areas/beds, row lines, nesting, mixed-variety plants and seasonal crop records.
- [x] Offline local trial; Firebase repository interfaces, persistence and security rules.
- [x] Supplied app icon and Android trial builds.

## Remaining product features

- [ ] Orchard rename/archive and explicit ownership transfer/deletion policies.
- [ ] Sharing: invitations, owner/editor/viewer permissions and collaboration UI.
- [ ] Foraging-resource entry, seasonality, observations and private/public visibility controls.
- [ ] Photo capture/gallery/upload, thumbnails and a durable offline upload queue.
- [ ] Task editing, recurring work, reminders, notifications and optional completion activities.
- [ ] Re-scope existing group checklists, add members explicitly and compare planned/completed work.
- [ ] Activity correction/voiding with an audit trail; richer harvest/yield reports.
- [ ] Uploaded/custom map icons and a consistent accessible symbol catalog.
- [ ] More map editing tools: move plants, split/join rows, vertex insertion and measurements.
- [ ] Export/import/backup and recovery of local trial records before installation changes.
- [ ] Connected account setup, sync/rejection recovery UI and multi-device acceptance testing.
- [ ] Stable private trial signing, production signing/distribution and installable iOS trial.
- [ ] Accessibility, field usability, small-screen and physical-device regression testing.

## Follow-up validation

- [ ] Verify Google Maps key authorization and imagery on a physical phone.
- [ ] Exercise GPS permission denial/approximate position and map-tile outages.
- [ ] Verify offline create/switch/restart across two orchards on physical Android/iOS devices.
- [ ] Verify Firestore reconnect, independent accounts, sign-out cache clearing and sync conflicts.

Large-scale taxonomy catalogs, public discovery and advanced analytics remain later
work. Google satellite downloads/offline tile packs are not promised by this app.
