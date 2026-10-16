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

### Plant records, archives and deletion

- [ ] Archived plants never appear on the map, including when other filters change. Add a dedicated **Archived Plants** list page, without a map, where archived plants can be viewed, fully edited and unarchived.
- [ ] Permanent deletion for a plant, area/bed or row, including its associated data. Plan the cascade for child sections, contained plants/crops, activities, harvests, tasks/completions, photos and stored files; show what will be removed before deletion. Remove orphaned references without deleting unrelated orchards, other plants' records or shared classification definitions.
- [ ] Full plant editing: allow changes to all user-facing plant fields, including **Group, Type and Variety**, location, planting date, row/bed assignment and other metadata. Preserve plant identity and history, and keep linked planting activities, classification views and matching tasks consistent with edits.

### Tasks, recurrence and linked activities

- [ ] Task sorting: default to **tasks without dates first**, followed by dated tasks with the closest next due date at the top. Let users change the sort order and automatically save/restore their choice across app restarts. Specify placement of overdue/completed tasks during design while preserving the requested undated/upcoming order.
- [ ] Dynamic group/matching-plant tasks: save the target criteria (including matching fruit/type), rather than only a creation-time snapshot. Automatically apply the task to plants added or becoming matches later, with completion still tracked per plant and existing completion records preserved. Allow creating and retaining a valid task even when **no plants currently match**.
- [ ] Repeating tasks: support yearly, monthly, weekly and other repeat schedules. Each occurrence starts with fresh per-plant completion state; retain all previous occurrences and their completion records instead of overwriting history.
- [ ] Optional task-to-activity link: when defining a plant task, optionally choose an activity/event type such as pruning. Completing that task also creates a linked event on the affected plant, visible in its activity history. Reopening the task removes its generated event. For group/repeating tasks, link completion and event per plant and occurrence; avoid duplicate events or removing unrelated/manual events. Reconcile these edit/removal requirements with the current append-oriented event model.
- [ ] Task and event/activity table filters: add filtering to both lists, with appropriate date, target and classification filters, task status and event type.
- [ ] Task editing, reminders and notifications beyond the sorting, matching, recurrence and activity-link features above.

### Activity editing and classification views

- [ ] Open an activity to edit its fields or delete it. Apply changes to plant history and derived harvest totals, including date/year and unit changes. Define how edits/deletion interact with a task-generated event and maintain consistent task/event links.
- [ ] Classification overview pages for **Group, Type and Variety**: view the matching plants' tasks, events/activities, harvests and totals together within the selected orchard. For example, **Type = Apple** includes tasks, events and harvests for all apple varieties. Keep harvest units separate and support the same classification hierarchy in list filters.

### Area versus Bed proposal — confirmation required before implementation

- [ ] Review removing the separate **Area** type and keeping only **Bed** and **Row**. **Do not implement this specific change until the user explicitly confirms the proposal.**
- Recommendation: use one polygon category labelled **Bed / Patch**, alongside **Row** for lines. Beds, raspberry patches and larger planting areas can share the same shape/nesting features, without two equivalent polygon types.
- If approved, migrate existing Area records into the retained polygon category while preserving IDs, names, geometry, nesting, contained plants/crops, tasks, activities, colors/icons and other references. Do not delete existing areas or their records as part of this consolidation.
- Confirmation still needed: approve this consolidation and the proposed **Bed / Patch** label, or choose **Bed** as the sole label instead. Existing Area/Bed behavior remains in place until that confirmation and a later implementation request.

### Other planned features

- [ ] Filter row/area visibility by plant type: when a plant-type filter is active, hide a row's line or an area's shape (and any associated icon) if it contains no plants matching that type. Keep rows/areas containing matching plants visible, including matches within nested sections, and restore normal visibility when the filter is cleared.
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
- [ ] Richer harvest/yield reports and activity audit/recovery design.
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
