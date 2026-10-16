# ADR-002: Trial plant management and tasks

Status: accepted implementation design. The attached [product specification](../ORCHARDATLAS_CODEX_SPEC.md) supplies the broader V1 roadmap. This increment implements the following usable trial features, rather than claiming all V1 acceptance criteria are complete.

## Planting dates and rapid entry

New, unrelated plants default to today's local calendar date. The date is optional and can be cleared. A similar plant inherits the source plant's date, including an explicitly unknown/cleared date. Repeated entry preserves the chosen date, rootstock and nursery. The user's current naming behavior takes precedence over the spec's older suggestion to clear names: custom names and automatic taxonomy names remain supported.

Creating a dated plant atomically creates exactly one planting activity. An undated plant creates no planting activity. Keep `plantedOn` as an optional YYYY-MM-DD metadata projection of the creation activity, not a UTC-derived date. Existing trial records derive missing plantedOn from the earliest recorded planting activity when available. A similar-plant template contains no identity, location, activity IDs or harvest history. Historical events remain append-only; this increment does not edit planting dates or historical events.

## Scope

- Plant metadata: optional rootstock, nursery/source, notes and captured GPS accuracy; detail overview.
- Edit name, rootstock, nursery/source and notes. Archive/restore plants without deleting events or tasks. Creation date, taxonomy, location and plantedOn remain unchanged by this metadata editor.
- Property-scoped search and taxonomy/status/planting-year filters, retained during navigation. Parent taxonomy filters traverse all descendants. The map and list use identical filters. Default hides archived plants.
- Basic tasks: property-wide or linked to a plant; title, notes, optional due date; open/completed/cancelled state; Today/This week/Upcoming/All views. No background notification claims.
- Expanded curated taxonomy, preserving existing UUIDs, and explicit bloom/lifecycle activity types. Foraging-oriented starter classifications do not imply a shipped foraging-resource workflow.
- Annual harvest display groups original units. Existing explicit kg conversion helpers remain tested but the default UI never combines lb/kg silently.

## Storage and security

Extend repository interfaces and both trial and Firestore adapters. Trial JSON additions are optional on read; keep the existing storage key and preserve old records. Persist plant plus planting event in one trial snapshot or one Firestore batch. Metadata edits and task status updates use deterministic last-submission-wins behavior; concurrent edits can overwrite metadata but cannot overwrite events. No sharing/public UI is added.

Firestore plants retain schemaVersion 1 and accept optional `plantedOn`, `rootstock`, `nursery`, `notes`, `status`, `accuracyMeters`. Validate all new values. New clients write these fields; old documents default to unknown date, empty strings, active status and unknown accuracy. Immutable plant identity fields cannot be changed through updates. Tasks live at `properties/{propertyId}/tasks/{taskId}` with UUID IDs, owner-only access, validated fields, immutable createdAt/itemId, and supported status transitions. Linked tasks must reference a plant in the same property; archived plants retain tasks. Task status can be reopened deliberately. No destructive delete.

## Explicit remaining scope

Nested places, foraging points/polygons, Google sign-in, photos/durable upload queue, local notifications, sharing and public discovery remain future increments. This trial stays local and private; connected adapters/rules are tested separately and do not constitute physical-device or cross-device acceptance. Google Maps switches to hybrid imagery in connected mode; the credential-free trial retains its labeled coordinate sketch.

## Verification and delivery

Test default/cleared/inherited dates and one planting event per creation; old trial save migration and restart durability; metadata and archive persistence; task creation/status/date filters; taxonomy descendant search; unit-separated harvest totals; strict mapping and Firestore ownership/validation rules. Run formatting/static analysis, Flutter tests, security-emulator tests, Android APK and iOS simulator CI where runners are available. Publish an Android trial artifact on the existing feature branch and keep PR #1 unmerged. Temporary debug signing remains a limitation for in-place phone updates; do not commit signing credentials.
