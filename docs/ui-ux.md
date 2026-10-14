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
   correction, explicit location confirmation. Save requires identity and valid
   confirmed position. Success navigates to detail without awaiting network sync.
4. **Plant Detail**: taxonomy breadcrumb, coordinates, annual selector with kg and
   count totals, ordered activity history, Record Activity and Add Another Like
   This actions. Cache/pending status distinguishes local state from confirmation.
5. **Record Activity**: type selector, selected date (defaults today), notes;
   harvest adds quantity and unit. Validate inline, prevent double submits.
   New event returns to detail and updates derived totals from the local stream.
6. **Add Another Like This**: preselect taxonomy and name; blank location until GPS
   or manual position is explicitly confirmed. Generate a new plant ID on save.

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
