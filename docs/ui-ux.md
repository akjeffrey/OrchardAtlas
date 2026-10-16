# UI and UX design

## Navigation and visual language
Material 3, orchard green seed color, readable outdoor contrast, generous targets,
and semantic labels. Map is the authenticated home. A plant-list tab provides an
accessible alternative and access when map tiles are absent. Keep input forms
scrollable above the keyboard. Every async page has loading, empty and error
states with recoverable actions. Never show raw credentials in errors.

## Screen flows
1. **Sign in**: email/password, sign-in and create-account actions; explain that
   first use needs Internet. Retain fields on a failed request.
2. **Map/list**: property title, cache/pending indicator, locate action, Add Plant.
   Markers are labeled by plant name; tap navigates to detail. GPS action centers
   map and shows accuracy. Tapping map sets an add location. If location fails,
   retain manual map selection. Do not silently use a hardcoded coordinate.
3. **Add Plant**: plant name; dependent group, genus, species, cultivar selectors;
   changing a parent clears descendants. Current-GPS button, lat/lon with manual
   correction and optional planting date. Save requires identity and valid
   coordinates. The post-save prompt offers another plant or centers the map without awaiting network sync; tap
   the marker to open detail.
4. **Plant Detail**: taxonomy breadcrumb, coordinates, annual selector with kg and
   count totals, ordered activity history, Record Activity and Add Another Like
   This actions. Cache/pending status distinguishes local state from confirmation.
5. **Record Activity**: type selector, selected date (defaults today), notes;
   harvest adds quantity and unit. Validate inline, prevent double submits.
   New event returns to detail and updates derived totals from the local stream.
6. **Add Another Like This**: preselect taxonomy and name, then fetch a fresh GPS
   position with manual correction available. Generate a new plant ID on save.

## Errors and accessibility
GPS denial explains manual entry and offers app settings for permanent denial.
Network-independent edits remain enabled after cached sign-in. Server rejection
appears as a persistent dismissible warning with the affected record ID; rejected
writes may disappear from local snapshots and must be re-entered after permissions
are restored. No claim that “pending” equals delivered. Semantic labels, standard
text scaling, keyboard types, and list alternative support nonvisual use.

## Deferred flows
Property chooser, role invitations, tasks, foraging patches, photos, and correction
history have no exposed unfinished buttons in V1. Test on small screens, at 200%
text scale, with TalkBack/VoiceOver, and outdoors before release.

## Phone trial feedback: plant entry

Each taxonomy dropdown includes **Add new option**. The dialog requires a name and a map icon from tree, apple, pear, berry, flower, citrus, nut, and vine symbols; it suggests the parent icon. The new UUID option belongs to this property and becomes selected immediately. Duplicate sibling names are rejected without regard to case. Icon selection is supported; custom image uploads are outside this iteration.

The plant name follows the deepest selected taxonomy label until the user enters a custom name. Changing an ancestor clears descendant selections and updates an automatic name. Clearing a custom name re-enables automatic naming; saving an empty name uses the selected species/cultivar label.

Planting date is optional and defaults to today for a new plant. A similar plant inherits the source date, including an unset date. A set date creates a dated planting activity in the same local submission as the plant. It is not inferred from the record creation timestamp. Leaving the date empty records no planting activity.

Add Plant requests foreground GPS automatically unless opened with an explicitly selected map position. It displays accuracy and editable coordinates. The former confirmation checkbox has been removed. A late GPS response never overwrites manual coordinate edits. Permission denial or unavailable GPS leaves manual entry available.

Saving opens **Plant added: Add another like this?**. Back to map focuses the saved plant. Add another keeps name, taxonomy, planting date, rootstock and source, clears unique notes and coordinates, and fetches a fresh GPS position. It never silently reuses the prior plant's position or activity history. Google Maps markers, trial coordinate markers, and the Plants list use the taxonomy icon.


## Trial management increment

Add Plant also offers rootstock, nursery/source and plant notes, and retains GPS accuracy when coordinates come from an unmodified GPS fix. Manual coordinate edits clear the accuracy claim. Detail shows this metadata and offers Edit, Archive/Restore and Plant tasks. The metadata editor does not rewrite planting history or captured location. Archived plants remain reachable through the status filter and keep events/tasks.

Home navigation is Map / Plants / Tasks. Plant search matches name, classification ancestors, rootstock, nursery and notes. Classification, year and status filters apply to both markers and list; active plants are the default. Filter state survives navigation during the session. Trial and connected maps default to Google satellite imagery when a native Maps key is configured. Full-screen mode hides data controls; Data mode restores them without resetting the camera or draft. Add row / Add area draws and saves directly on the map. Map location search accepts decimal latitude/longitude locally or device-geocoder address results; it is separate from the plant filter. Without a configured key an explicit coordinate sketch is shown.

Tasks can target the property or a plant. They have a title, notes, optional due date and open/completed/cancelled status, with explicit completion, cancellation and reopening controls. Today and This week include overdue tasks; Upcoming includes dates beyond the current week plus undated tasks. Task due dates do not schedule notifications in this increment.

The activity picker includes explicit bloom stages, pests, disease, damage, harvest start/end, death and observation. Annual harvest summaries display each recorded unit separately; no default conversion combines pounds and kilograms.
