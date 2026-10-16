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

- [ ] Android immersive display: hide the bottom Android system navigation buttons/bar while OrchardAtlas is open, where supported by the Android version and navigation mode. Preserve the system gesture to temporarily reveal navigation controls and restore normal system navigation when leaving the app.
- [ ] Simplify plant classification selectors to **Group → Type → Variety**: keep Group, rename Genus to Type and Species to Variety, and remove the Cultivar selector entirely. Plan how existing cultivar selections and custom taxonomy remain usable when moving to the three-level selection flow.
- [ ] Areas, Beds & Rows page basemap: use Google Maps with the app's default satellite view beneath the orchard's area/bed polygons and row lines, so their full shapes are shown over geographic imagery.
- [ ] Row and area colors: let users choose and save a color for each row and each area, while continuing to display the complete row line or area shape on the map.
- [ ] Optional row/area icons: let users choose an optional icon displayed at the center of the row or area, in addition to its full colored line or shape.
- [ ] Plant location in rows/areas: when adding a plant to a row or area, default its location to that row or area's location.
- [ ] Map markers for grouped plants: hide individual plant icons on the map when the plant belongs to a row or area; keep the parent row/area visible and the plants accessible through it.
- [ ] Row endpoints and direction: explicitly track start (first point) and stop/finish point(s).
- [ ] Default plant ordering within a row: sequence newly added row plants from the start toward the finish.
- [ ] Manual row plant ordering: let users rearrange plants while viewing a row (for example, drag-and-drop or move up/down), and persist the revised order.
- [ ] Orchard naming: let users edit an orchard's name. On a fresh app install, name the automatically created first orchard "Home Orchard". Preserve existing orchard names and records during upgrades.
- [ ] Orchard archive and explicit ownership transfer/deletion policies.
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
