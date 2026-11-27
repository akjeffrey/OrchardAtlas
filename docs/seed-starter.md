# Seed Starter: first tray-management slice

The orchard's main tabs are Map, Plants, Tasks, then **Seed Starter**. The tab bar
scrolls horizontally. Seed Starter lists multiple named trays for the selected
orchard. Add tray asks for its name, row count and column count; its interactive
visual grid has exactly those dimensions. This is a tappable generated layout,
not a static bitmap. Dimensions are fixed after creation to preserve positions.
Names can be changed without changing tray or cell identities.

Tap cells to toggle individual selection. R headers toggle entire rows and C
headers toggle entire columns. Intersections are selected once. Select all and
Clear selection are available. The grid pans and zooms in both directions; cells have
visible boundaries, selected styling and accessible position/content labels.

Add seed / plant opens a shared Group → Type → Variety picker, a Seed/Plant
choice, optional cell label, and icon selection. Classification icons are the
default; built-in and custom overrides are optional. Applying fills every
selected cell. Replacing occupied cells asks for confirmation. Clear cell
contents also requires confirmation. Deleted custom icons use the existing
question-mark fallback. These operations do not create a mapped plant or plant activity. Germination
and detailed tray-history features remain deferred.

## Domain and persistence

`SeedTrayRepository` separates UI/providers from local and Firestore adapters.
SeedTray has a UUID, orchard ID, validated name, immutable dimensions and creation
time. Limits are 1–24 per dimension and at most 400 cells. Positions are 1-based
row/column values. Cell document keys combine the tray UUID and position; cells
are positional values rather than independent plant entities. Assignments hold
the classification UUID, Seed/Plant kind, label, assigned timestamp and optional
icon override.

Local seedTray/seedCell records are part of existing orchard snapshots and Drive
archives. Restore validates layouts, record versions and cell bounds before
mutation. There is no migration for old backups: missing tray records mean an
empty tray list. Other orchards and trays remain isolated. A local selection is
written in one snapshot. Connected assignments use batches of at most 400 cell
writes; unrelated cell documents are preserved. Same-cell concurrent edits use
Firestore's normal last-write behavior. Offline writes use the existing
submission/error-observation flow and Firestore persistence.

Firestore rules allow owner/editor writes and viewer reads. Layout changes are
rejected after creation. Cell identity, tray association and coordinates are
immutable; out-of-bounds cells and invalid icon references are rejected. Connected
installations must deploy the updated rules. The phone APK needs no new secrets.

## Validation

Tests cover grid dimensions/selection unions, mapping, independent cell writes,
rename/restart, orchard isolation, backup restoration, UI creation/assignment and
server permission/bounds checks. CI performs formatting, static analysis, full
Flutter/security suites, native builds and signed APK verification.

## Planting and transplantation

New cell plantings default their planting date to today; it can be edited or
cleared. Enter an optional whole number of days until transplant (0–3650). An
expected transplant date is derived from the planting date plus that interval;
unknown dates in old records remain unknown. Select an occupied cell and open
Add seed / plant to review/edit its dates and packet photos. Date details are
also exposed in cell tooltips/accessibility labels.

Record transplant applies an actual chosen date to the selected occupied cells.
It cannot precede a known planting date. Cells remain occupied with their label,
photos and classification, but have grey fill, dimmed icons and a check mark.
Undo transplant clears the actual date and restores the growing appearance.
These records do not automatically create a plant at a new map location.

## Seed-packet photos

The planting form provides separate front and back camera/gallery controls.
Cancelled edits discard draft photos. Confirming a planting saves new photo
metadata and cells in one local snapshot or Firestore batch (at most 402 writes).
A bulk selection shares two photo references instead of duplicating the bytes in
every cell. Existing capture limits/thumbnails, offline upload queue and Storage
rules apply. Original planting dates and photo references survive transplantation.
Local snapshots/Drive backups include photos subject to the existing 20 MiB
archive limit; full uploaded photos use authenticated Storage and offline
thumbnails. Replaced/unlinked photos remain with their tray until tray deletion,
since other cells can still reference the same packet.

## Tray deletion

Delete tray asks for confirmation and removes all its cell assignments and packet
photo records. Local deletion persists offline immediately. Connected deletion
requires server access and also removes stored photo objects. A deleting marker
blocks new cell/photo entries during cleanup. If connectivity or deletion fails,
the tray remains visible with a retry message; repeat Delete tray to finish the
idempotent cleanup. Other trays and orchard records are unaffected. In-flight
uploads whose metadata was removed are discarded/cleaned up by the upload worker.
Deploy updated Firestore rules before using connected lifecycle/photo features.

## Zoom and packet-photo cell icons

Pinch to zoom, drag to pan, or use Zoom in / Zoom out, Fit tray and Reset tray zoom (100%). The grid is clipped to its own viewport so controls remain accessible. Zoom is bounded from 1% to 300%; fitting uses the available grid viewport. Row/column selectors, cell selection and grey transplanted cells remain functional after transforms. Zoom/pan are local viewing state, not part of the orchard data.

In Add seed / plant, capture or choose a front seed-packet photo, then enable **Use packet front photo as cell icon**. The choice applies to every selected cell and is editable for an existing single cell. Removing the front photo switches back to its retained classification/custom icon. Replacing the front image updates the icon reference; transplantation retains the choice and dims the thumbnail. Missing/corrupt thumbnails fall back to the normal icon. Thumbnails use the existing shared photo record, bounded image cache and offline/Drive backup data; no full-image downloads or duplicate per-cell photos are needed. Old assignments default the optional `usePacketFrontIcon` flag to false. Connected installations must deploy the updated Firestore cell rules.
