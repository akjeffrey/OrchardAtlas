# OrchardAtlas feature backlog

GitHub issues are the source of truth for outstanding work: [open tickets](https://github.com/akjeffrey/OrchardAtlas/issues). This document keeps an issue-linked index and implementation history. Keep links and completed status current in each feature PR. `[ ]` is planned, `[~]` is in progress, and `[x]` is implemented. Implementation does not replace physical-device checks.

## Newly requested features

- [x] **Version History:** add a page in Settings and Orchard options with the installed version’s changes and four prior feature updates; keep the five-update history current for future releases.
- [x] [#62](https://github.com/akjeffrey/OrchardAtlas/issues/62) **Seasonal planting classification selectors:** use the same cascading Group → Type → Variety dropdowns as Add Plant, including consistent catalog/custom-option behavior. Preserve the other seasonal planting draft fields.
- [x] [#63](https://github.com/akjeffrey/OrchardAtlas/issues/63) **Annual/perennial conversion:** let users convert an existing plant in either direction while preserving classification, location, metadata, history and task/harvest links. Change management in place without moving storage records; ask for a season when needed and persist conversions offline and in backups.
- [x] [#64](https://github.com/akjeffrey/OrchardAtlas/issues/64) **Matching icons on the Plants page:** show each plant's map icon in the plant list, using the same classification inheritance, built-in/custom imagery and question-mark fallback. Keep list icons small and update them consistently with map icon changes.
- [x] [#65](https://github.com/akjeffrey/OrchardAtlas/issues/65) **Hierarchical task target selection:** default to Whole orchard, with optional Group → Type → Variety dropdowns like Add Plant. Group-only and Type-only targets include all matching descendant plants; keep Type/Variety optional and preserve dynamic membership, per-plant progress and task history.
- [x] [#66](https://github.com/akjeffrey/OrchardAtlas/issues/66) **Show on Map from Edit Plant:** add a Show on Map button that switches to the correct orchard's map, centers on the plant and displays its anchored name as after a first tap. Handle unsaved edits explicitly and support plants whose normal markers are hidden by Area/Row membership.
- [x] **Versioned app presentation:** replace visible trial labels with OrchardAtlas and the installed version. Name downloadable APK/ZIP artifacts with the version; retain the existing internal package ID, storage keys and signing identity so updates preserve data.
- [x] [#59](https://github.com/akjeffrey/OrchardAtlas/issues/59) **Small dots for row endpoints:** replace the map flag/pin indicators at row start and stop (finish) with small dots. Keep start/finish distinguishable, retain their labels and selection behavior, and keep dot sizes modest across zoom levels. Preserve row geometry, direction, plant ordering and optional center icons.
- [x] [#57](https://github.com/akjeffrey/OrchardAtlas/issues/57) **Rename custom icons:** let users edit an existing custom icon's name from Settings → Custom icons, with Save/Cancel and nonblank-name validation. Preserve its UUID, image and all existing assignments, update displayed names throughout icon choices, and persist changes offline, across restart and in backups. Deleted icons remain deleted.
- [x] [#55](https://github.com/akjeffrey/OrchardAtlas/issues/55) **Create classification options while editing a plant:** enable adding custom Groups, Types and Varieties directly from Edit Plant, like Add Plant. Keep options scoped to the orchard and the selected parent, support existing icon choices, and select the new option in the draft without losing other edits. Save plant classification changes only when the user saves the plant; preserve identity/history and persist new options offline and in backups.
- [x] [#53](https://github.com/akjeffrey/OrchardAtlas/issues/53) **Choose a new plant location on the map:** Add Plant offers the same map picker as Edit Plant. Add Another, both after saving and from detail, starts at the previous plant’s location; GPS remains an explicit option.
- [x] [#51](https://github.com/akjeffrey/OrchardAtlas/issues/51) **Use restored file for automatic backups:** after a successful backup restore, ask whether that file should become the destination for future automatic backups, with **Yes** selected by default. Persist the destination and file access across restart if accepted; retain the existing destination if declined. Handle read-only files or unavailable persistent access without claiming backup is configured.
- [x] [#49](https://github.com/akjeffrey/OrchardAtlas/issues/49) **Names anchored to map features:** on the first tap of a plant, Area or Row, show its name in a tag attached to that feature instead of at the top of the map. Match the labels seen after editing and returning to the map in version 0.35, without requiring that round trip. Keep the tag anchored during pan/zoom and preserve second-tap Plant Detail navigation.
- [x] [#47](https://github.com/akjeffrey/OrchardAtlas/issues/47) **Delete custom icons:** allow deletion of imported icons from Settings. Plants using a deleted icon, including through Group/Type/Variety inheritance, must display a question-mark icon. Preserve plant data and persist the fallback across restart and backup/restore without dangling icon references. Areas/Rows using deleted custom icons also show a question mark. Deletion removes image bytes and keeps a small tombstone so offline references and backups remain valid.
- [x] [#20](https://github.com/akjeffrey/OrchardAtlas/issues/20) **Classification settings:** add a Settings page for editing the available **Group, Type and Variety** options, including their names and associated icons. Keep the hierarchy consistent and preserve stable option IDs so existing plants, task criteria, history and classification views continue to reference the edited options. This manages the options themselves, separately from changing a single plant's classification.
- [x] [#21](https://github.com/akjeffrey/OrchardAtlas/issues/21) **Custom icon uploads:** let users import new icons from their device and select them wherever map icons are supported, including classification options and optional Area/Row icons. Normalize imported images to small thumbnails with bounded dimensions and file sizes, preserving transparency where present. Persist the icon library and assignments locally and include them in backup/restore so an imported icon remains usable after restart or device migration.
- [x] [#22](https://github.com/akjeffrey/OrchardAtlas/issues/22) **Map icon sizing across zoom levels:** cap marker icons at a modest screen size, including imported icons, so large source images cannot create oversized markers. Keep icons small or reduce/simplify them as the map zooms out; they must not grow as more of the orchard becomes visible. Apply consistent sizing to plant and optional Area/Row icons, with usable tap targets and checks at close and wide zoom levels.
- [x] [#23](https://github.com/akjeffrey/OrchardAtlas/issues/23) **Two-tap plant marker navigation:** the first tap on a plant marker shows only the plant's name without opening its detail page. A second tap on the same selected marker opens Plant Detail. Tapping a different marker starts with that plant's name; tapping the map background clears the selection. Coordinate marker and info-window callbacks to avoid opening details on the first tap or navigating twice.

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

- [x] Map-based plant location editing: add a **Pick location on map** action to the plant editor. Open Google Maps in satellite view centered on the plant's current position, let the user tap a new spot or drag its pin, and confirm the selection to update the editor's latitude and longitude. Save the new location with the plant's other edits; cancel keeps the previous coordinates. Preserve the plant's identity, history and Area/Row assignment.

- [x] Archived plants never appear on the map, including when other filters change. Add a dedicated **Archived Plants** list page, without a map, where archived plants can be viewed, fully edited and unarchived.
- [x] Permanent deletion for a plant, area or row, including its associated data. Plan the cascade for child sections, contained plants/crops, activities, harvests, tasks/completions, photos and stored files; show what will be removed before deletion. Remove orphaned references without deleting unrelated orchards, other plants' records or shared classification definitions.
- [x] Full plant editing: allow changes to all user-facing plant fields, including **Group, Type and Variety**, location, planting date, row/area assignment and other metadata. Preserve plant identity and history, and keep linked planting activities, classification views and matching tasks consistent with edits.

### Tasks, recurrence and linked activities

- [x] Task sorting: default to **tasks without dates first**, followed by dated tasks with the closest next due date at the top. Let users change the sort order and automatically save/restore their choice across app restarts. Specify placement of overdue/completed tasks during design while preserving the requested undated/upcoming order.
- [x] Dynamic group/matching-plant tasks: save the target criteria (including matching fruit/type), rather than only a creation-time snapshot. Automatically apply the task to plants added or becoming matches later, with completion still tracked per plant and existing completion records preserved. Allow creating and retaining a valid task even when **no plants currently match**.
- [x] Repeating tasks: support yearly, monthly, weekly and other repeat schedules. Each occurrence starts with fresh per-plant completion state; retain all previous occurrences and their completion records instead of overwriting history.
- [x] Optional task-to-activity link: when defining a plant task, optionally choose an activity/event type such as pruning. Completing that task also creates a linked event on the affected plant, visible in its activity history. Reopening the task removes its generated event. For group/repeating tasks, link completion and event per plant and occurrence; avoid duplicate events or removing unrelated/manual events. Reconcile these edit/removal requirements with the current append-oriented event model.
- [x] Task and event/activity table filters: add filtering to both lists, with appropriate date, target and classification filters, task status and event type.
- [x] [#24](https://github.com/akjeffrey/OrchardAtlas/issues/24) Task editing, reminders and notifications beyond the sorting, matching, recurrence and activity-link features above.

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
- [ ] [#25](https://github.com/akjeffrey/OrchardAtlas/issues/25) Orchard archive and explicit ownership transfer/deletion policies.
- [x] [#26](https://github.com/akjeffrey/OrchardAtlas/issues/26) Sharing: invitations, owner/editor/viewer permissions and collaboration UI.
- [x] [#27](https://github.com/akjeffrey/OrchardAtlas/issues/27) Foraging-resource entry, seasonality, observations and private/public visibility controls.
- [x] [#28](https://github.com/akjeffrey/OrchardAtlas/issues/28) Photo capture/gallery/upload, thumbnails and a durable offline upload queue.
- [x] [#29](https://github.com/akjeffrey/OrchardAtlas/issues/29) Richer harvest/yield reports and activity audit/recovery design.
- [ ] [#30](https://github.com/akjeffrey/OrchardAtlas/issues/30) Consistent accessible symbol catalog; custom icon imports and sizing are tracked under **Newly requested features**.
- [ ] [#31](https://github.com/akjeffrey/OrchardAtlas/issues/31) More map editing tools: split/join rows, vertex insertion and measurements. Plant movement via a map picker is already implemented.
- [x] Android trial JSON backup/restore through the system file picker, including Google Drive, all orchards, pre-restore recovery and default external-file retention. Automatic writes wait for one minute without new edits (resetting after each edit), with local-first saves, failed-write retries and restart catch-up. See drive-backup-and-updates.md.
- [ ] [#32](https://github.com/akjeffrey/OrchardAtlas/issues/32) Cross-platform backup and recovery beyond the Android local trial.
- [ ] [#33](https://github.com/akjeffrey/OrchardAtlas/issues/33) Connected account setup, sync/rejection recovery UI and multi-device acceptance testing.
- [x] Update-safe Android trial signing pipeline and semantic 0.N.0 build versions. Publishing requires the one-time private signing secret described in drive-backup-and-updates.md.
- [ ] [#34](https://github.com/akjeffrey/OrchardAtlas/issues/34) Production signing/distribution and installable iOS trial.
- [ ] [#35](https://github.com/akjeffrey/OrchardAtlas/issues/35) Accessibility, field usability, small-screen and physical-device regression testing.

## Follow-up validation

- [ ] [#36](https://github.com/akjeffrey/OrchardAtlas/issues/36) Verify Google Maps key authorization and imagery on a physical phone.
- [ ] [#37](https://github.com/akjeffrey/OrchardAtlas/issues/37) Exercise GPS permission denial/approximate position and map-tile outages.
- [ ] [#38](https://github.com/akjeffrey/OrchardAtlas/issues/38) Verify offline create/switch/restart across two orchards on physical Android/iOS devices.
- [ ] [#39](https://github.com/akjeffrey/OrchardAtlas/issues/39) Verify Firestore reconnect, independent accounts, sign-out cache clearing and sync conflicts.

## Later-stage tickets

- [ ] [#40](https://github.com/akjeffrey/OrchardAtlas/issues/40) Support large-scale taxonomy catalogs.
- [ ] [#41](https://github.com/akjeffrey/OrchardAtlas/issues/41) Add public discovery with sanitized location visibility.
- [ ] [#42](https://github.com/akjeffrey/OrchardAtlas/issues/42) Explore advanced orchard analytics.

Google satellite downloads/offline tile packs are not promised by this app.

## Latest delivered additions

- [x] [#69](https://github.com/akjeffrey/OrchardAtlas/issues/69) Plant Detail **Show on Map**, matching Edit Plant focus and Back navigation.
- Implementation, availability and setup for #24/#26/#27/#28/#29: [sharing, media, reminders and reports](collaboration-photos-reminders-reports.md). Connected roles/public publishing/Storage require Firebase; the local APK retains local-first capture and Drive backup.

- [x] Foraging as a remembered home mode in the Mode & orchard switcher, with its own resource map/list. Shared icon-inspired form theme. See [mode and theme design](foraging-mode-and-visual-theme.md).

- [x] Tap-to-pin foraging capture, preserving the selected spot through map movement; native **Share find** summaries in the local and connected builds.
