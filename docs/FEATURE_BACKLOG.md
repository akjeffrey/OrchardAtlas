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
- [x] Areas, row lines, nesting, mixed-variety plants and seasonal crop records.
- [x] Offline local trial; Firebase repository interfaces, persistence and security rules.
- [x] Supplied app icon and Android trial builds.

## Remaining product features

### Plant records, archives and deletion

- [ ] Map-based plant location editing: add a **Pick location on map** action to the plant editor. Open Google Maps in satellite view centered on the plant's current position, let the user tap a new spot or drag its pin, and confirm the selection to update the editor's latitude and longitude. Save the new location with the plant's other edits; cancel keeps the previous coordinates. Preserve the plant's identity, history and Area/Row assignment.

- [x] Archived plants never appear on the map, including when other filters change. Add a dedicated **Archived Plants** list page, without a map, where archived plants can be viewed, fully edited and unarchived.
- [x] Permanent deletion for a plant, area or row, including its associated data. Plan the cascade for child sections, contained plants/crops, activities, harvests, tasks/completions, photos and stored files; show what will be removed before deletion. Remove orphaned references without deleting unrelated orchards, other plants' records or shared classification definitions.
- [x] Full plant editing: allow changes to all user-facing plant fields, including **Group, Type and Variety**, location, planting date, row/area assignment and other metadata. Preserve plant identity and history, and keep linked planting activities, classification views and matching tasks consistent with edits.

### Tasks, recurrence and linked activities

- [x] Task sorting: default to **tasks without dates first**, followed by dated tasks with the closest next due date at the top. Let users change the sort order and automatically save/restore their choice across app restarts. Specify placement of overdue/completed tasks during design while preserving the requested undated/upcoming order.
- [x] Dynamic group/matching-plant tasks: save the target criteria (including matching fruit/type), rather than only a creation-time snapshot. Automatically apply the task to plants added or becoming matches later, with completion still tracked per plant and existing completion records preserved. Allow creating and retaining a valid task even when **no plants currently match**.
- [x] Repeating tasks: support yearly, monthly, weekly and other repeat schedules. Each occurrence starts with fresh per-plant completion state; retain all previous occurrences and their completion records instead of overwriting history.
- [x] Optional task-to-activity link: when defining a plant task, optionally choose an activity/event type such as pruning. Completing that task also creates a linked event on the affected plant, visible in its activity history. Reopening the task removes its generated event. For group/repeating tasks, link completion and event per plant and occurrence; avoid duplicate events or removing unrelated/manual events. Reconcile these edit/removal requirements with the current append-oriented event model.
- [x] Task and event/activity table filters: add filtering to both lists, with appropriate date, target and classification filters, task status and event type.
- [ ] Task editing, reminders and notifications beyond the sorting, matching, recurrence and activity-link features above.

### Activity editing and classification views

- [x] Open an activity to edit its fields or delete it. Apply changes to plant history and derived harvest totals, including date/year and unit changes. Define how edits/deletion interact with a task-generated event and maintain consistent task/event links.
- [x] Classification overview pages for **Group, Type and Variety**: view the matching plants' tasks, events/activities, harvests and totals together within the selected orchard. For example, **Type = Apple** includes tasks, events and harvests for all apple varieties. Keep harvest units separate and support the same classification hierarchy in list filters.

### Single polygon type: Area

- [x] Consolidate the equivalent area, bed and patch concepts into one polygon type named **Area**. Keep **Row** for lines. Remove the separate Bed type and do not introduce a separate Patch type.
- The user has confirmed **Area** as the single word to use throughout the UI for this concept. The display label can be changed later without creating multiple types for the same concept.
- [x] Migrate existing Bed records to Area while preserving IDs, user-entered names, geometry, nesting, contained plants/crops, tasks, activities, colors/icons and other references. Existing Area records remain intact; patches are represented as Areas. This consolidation must not delete records or rename users' individual planting locations.
- Implemented with compatibility reads for legacy Bed records; subsequent saves use Area.

### Other planned features

- [x] Filter row/area visibility by plant type: when a plant-type filter is active, hide a row's line or an area's shape (and any associated icon) if it contains no plants matching that type. Keep rows/areas containing matching plants visible, including matches within nested sections, and restore normal visibility when the filter is cleared.
- [x] Android immersive display: hide the bottom Android system navigation buttons/bar while OrchardAtlas is open, where supported by the Android version and navigation mode. Preserve the system gesture to temporarily reveal navigation controls and restore normal system navigation when leaving the app.
- [x] Simplify plant classification selectors to **Group → Type → Variety**: keep Group, rename Genus to Type and Species to Variety, and remove the Cultivar selector entirely. Plan how existing cultivar selections and custom taxonomy remain usable when moving to the three-level selection flow.
- [x] Areas & Rows page basemap (currently Areas, Beds & Rows): use Google Maps with the app's default satellite view beneath the orchard's Area polygons and Row lines, so their full shapes are shown over geographic imagery.
- [x] Row and area colors: let users choose and save a color for each row and each area, while continuing to display the complete row line or area shape on the map.
- [x] Optional row/area icons: let users choose an optional icon displayed at the center of the row or area, in addition to its full colored line or shape.
- [x] Plant location in rows/areas: when adding a plant to a row or area, default its location to that row or area's location.
- [x] Map markers for grouped plants: hide individual plant icons on the map when the plant belongs to a row or area; keep the parent row/area visible and the plants accessible through it.
- [x] Row endpoints and direction: explicitly track start (first point) and stop/finish point(s).
- [x] Default plant ordering within a row: sequence newly added row plants from the start toward the finish.
- [x] Manual row plant ordering: let users rearrange plants while viewing a row (for example, drag-and-drop or move up/down), and persist the revised order.
- [x] Orchard naming: let users edit an orchard's name. On a fresh app install, name the automatically created first orchard "Home Orchard". Preserve existing orchard names and records during upgrades.
- [ ] Orchard archive and explicit ownership transfer/deletion policies.
- [ ] Sharing: invitations, owner/editor/viewer permissions and collaboration UI.
- [ ] Foraging-resource entry, seasonality, observations and private/public visibility controls.
- [ ] Photo capture/gallery/upload, thumbnails and a durable offline upload queue.
- [ ] Richer harvest/yield reports and activity audit/recovery design.
- [ ] Uploaded/custom map icons and a consistent accessible symbol catalog.
- [ ] More map editing tools: move plants, split/join rows, vertex insertion and measurements.
- [x] Android trial JSON backup/restore through the system file picker, including Google Drive, all orchards, pre-restore recovery and default external-file retention. Automatic writes wait for one minute without new edits (resetting after each edit), with local-first saves, failed-write retries and restart catch-up. See drive-backup-and-updates.md.
- [ ] Cross-platform backup and recovery beyond the Android local trial.
- [ ] Connected account setup, sync/rejection recovery UI and multi-device acceptance testing.
- [x] Update-safe Android trial signing pipeline and semantic 0.N.0 build versions. Publishing requires the one-time private signing secret described in drive-backup-and-updates.md.
- [ ] Production signing/distribution and installable iOS trial.
- [ ] Accessibility, field usability, small-screen and physical-device regression testing.

## Follow-up validation

- [ ] Verify Google Maps key authorization and imagery on a physical phone.
- [ ] Exercise GPS permission denial/approximate position and map-tile outages.
- [ ] Verify offline create/switch/restart across two orchards on physical Android/iOS devices.
- [ ] Verify Firestore reconnect, independent accounts, sign-out cache clearing and sync conflicts.

Large-scale taxonomy catalogs, public discovery and advanced analytics remain later
work. Google satellite downloads/offline tile packs are not promised by this app.
