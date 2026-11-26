# Seed Starter: first tray-management slice

The orchard's main tabs are Map, Plants, Tasks, then **Seed Starter**. The tab bar
scrolls horizontally. Seed Starter lists multiple named trays for the selected
orchard. Add tray asks for its name, row count and column count; its interactive
visual grid has exactly those dimensions. This is a tappable generated layout,
not a static bitmap. Dimensions are fixed after creation to preserve positions.
Names can be changed without changing tray or cell identities.

Tap cells to toggle individual selection. R headers toggle entire rows and C
headers toggle entire columns. Intersections are selected once. Select all and
Clear selection are available. The grid scrolls in both directions; cells have
visible boundaries, selected styling and accessible position/content labels.

Add seed / plant opens a shared Group → Type → Variety picker, a Seed/Plant
choice, optional cell label, and icon selection. Classification icons are the
default; built-in and custom overrides are optional. Applying fills every
selected cell. Replacing occupied cells asks for confirmation. Clear cell
contents also requires confirmation. Deleted custom icons use the existing
question-mark fallback. None of these operations creates a mapped plant or a
plant activity; germination, transplanting and tray-history features are deferred.

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
