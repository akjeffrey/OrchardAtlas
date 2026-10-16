# ADR-003: Group tasks, orchard layout and seasonal plantings

Status: accepted design for Trial 0.3. Commit this design before application changes.

## Group tasks

Create one group from active plants matching an optional taxonomy ancestor and/or orchard section (including descendants). Snapshot membership at creation; new plants are not silently added, archived targets remain in the checklist. One UUID group links individual UUID task records. Reuse existing per-plant status storage and derive group progress from every member, regardless of list filters. Each member can be completed, reopened, cancelled or skipped independently; completion stores its local calendar date. Creating the group is atomic, limited to 400 members per submission. No automatic pruning events: checking a task does not assert a separate observation; activity recording remains explicit.

The task form also supports directly targeting a row/area or seasonal crop. Group progress shows completed, skipped/cancelled and remaining counts. Group detail includes every target so work can continue across days. Property-wide and individual tasks remain supported.

## Layout

OrchardSection has id, propertyId, name, kind (area/bed/row), parentId, vertices, notes and createdAt. Rows are polylines with at least two distinct points; areas/beds are simple polygons with at least three distinct, non-collinear vertices and no self-intersections. Store polygon vertices without a repeated final vertex; renderers close them. Maximum 40 vertices; WGS84 coordinates, no antimeridian-crossing geometry in this increment. Parent sections must be areas/beds in the same property, with no cycles. Preserve section identity and parent when editing name, notes and geometry. No destructive deletion.

A drawing editor uses a credential-free coordinate sketch in trial mode and Google Maps in connected mode. Tap to append vertices, undo, enter coordinates manually, or capture GPS. Users may reposition vertices through the coordinate list. Existing sections render on the home map; outlines and labels are also available without basemap imagery. Nested lists and section detail provide a fallback.

Plants have an optional sectionId; add/edit can assign a plant to a row, bed or area. Similar entry preserves this assignment. Section detail lists plants and nested sections, allowing mixed blueberry varieties in one row. Physical membership is explicit, not automatically inferred from approximate GPS boundaries.

## Seasons

CropPlanting has id, propertyId, sectionId, taxonId, label, season label/year, plantedOn (optional), notes, createdAt, status (growing/harvested/ended), harvestedOn (optional). It represents a crop occupying a permanent row/bed, not a replacement of that layout. Multiple crop records allow variety sections in one row; permanent blueberry bushes remain individual ManagedPlants. Garlic bed → rows → yearly variety plantings is the primary seasonal workflow. Raspberry patches may be represented as an area with a crop record without entering each cane.

Record a harvest date or end a crop while preserving classification, planting date and earlier seasons. Replant by creating a new UUID record prefilled from an earlier crop; never overwrite its season. Optional seasonal harvest quantities are separate UUID harvest records, grouped by original unit and activity year, append-only. A harvested crop may still receive additional harvest records; ended crops remain historical. Section detail shows current crops and history, with links to crop detail and tasks.

## Persistence, privacy and icons

Extend repository contracts, local trial JSON and Firestore adapters. Old saves default to no sections/crops/group IDs. Trial changes share the serialized local write queue; Firestore uses property-scoped collections (sections/crops/cropHarvests) and native offline persistence. Task group creation uses a batch. Crop/task targets must reference records in the same property. To keep group creation atomic for up to 400 plants within Firestore’s 20-document-access rule limit, group-member writes validate UUID shape and owner scope without a per-member existence lookup. The application validates snapshot membership against property-scoped plants; forged orphan IDs cannot grant access to another property or its data. Individual task targets retain server existence checks. New paths remain owner-only; strict field validation, immutable identity/parent/classification and append-only harvests. Section hierarchy/geometry topology is validated in the domain and local adapter; server rules additionally constrain coordinate ranges, shape, vertex count, parent kind and immutable parentage. Geometry edits are last-update-wins; independent task members and append-only harvests minimize conflicts.

Use the user's Option 1 PNG artwork for Android launcher density assets and all iOS app-icon slots. Preserve the supplied source and provenance. Resize supplied artwork for required slots; do not invent an adaptive foreground from the flattened design. No signing credentials are committed. Existing temporary debug-signing update limits still apply.

## Acceptance

Create a garlic bed polygon with two named row lines; add distinct yearly garlic varieties and a later season without losing history. Create a raspberry area/crop. Assign mixed blueberry bushes to a row. Create an Apple group task, complete one tree, skip another, restart, and verify dates/progress and remaining work. Verify taxonomy and section descendant selection, parent/geometry validation, migration, repository mappings, per-target authorization and independent writes. Run static analysis, Flutter tests, security emulator tests and native CI; publish an updated trial APK and keep PR #1 unmerged. Connected-device and cross-device verification remain manual.
