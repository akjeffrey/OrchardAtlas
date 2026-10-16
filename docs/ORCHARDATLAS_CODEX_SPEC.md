# OrchardAtlas — Product, Architecture, and V1 Implementation Specification

**Status:** Implementation baseline for Codex
**Repository:** `akjeffrey/OrchardAtlas`
**Platforms:** Android first, iOS compatible
**Implementation:** Flutter / Dart
**Revision:** 1.0 — 2026-10-14

## 1. Instructions to Codex

Implement OrchardAtlas in the existing repository. **First commit all design/architecture documents**, then implement V1 on a feature branch and open a pull request to `main`; do not merge. Read the complete specification before editing. Preserve separation of concerns and write tests. Do not claim runtime tests passed unless executed. If external credentials, Google Cloud billing, signing, or Firebase configuration are unavailable, provide functional local/demo mode and explicit setup instructions; do not fake cloud synchronization or GPS functionality.

This document consolidates the decisions reached in the initial design conversation. Where implementation details were not decided, use documented engineering judgment and capture decisions in ADRs. Prioritize a genuinely executable and testable application over decorative scaffolding.

## 2. Vision and Users

OrchardAtlas is an offline-first mobile system of record for **orchards, gardens, managed plants, and foraging locations**. It combines a satellite map, GPS and manual placement, hierarchical classification, observations and lifecycle history, harvest accounting, tasks/reminders, photos, and controlled sharing. The app should be useful while walking among dozens of trees or foraging in woods with no cellular connection.

Primary scenarios:
1. Walk to an existing apple tree; capture or adjust its GPS location; classify it Fruit Tree → Apple → Honeycrisp; record planting year and rootstock; save it; repeat quickly for the next tree.
2. Find a tree on a satellite map; review its full activity history; record full bloom, pruning, spraying, or a harvest; see harvest totals by year.
3. Record a private morel patch as a point or polygon; add observations over multiple years; optionally share with trusted people.
4. Create a reminder to fertilize a particular tree, prune a group, or check a foraging patch.
5. Make records offline, close and reopen the app, then synchronize to the user's other device once online.

## 3. Scope and Priorities

### 3.1 V1 required features

- Flutter app shell, navigation, loading/empty/error states, accessible controls.
- Google sign-in/Firebase Authentication for connected mode; clear onboarding and logged-out handling.
- Google Maps with satellite/hybrid view, device location permission, current-location control, plant/foraging markers, marker selection, map zoom/pan.
- Property and nested Place organization; point and polygon geometry for places/foraging resources; point geometry for individual plants.
- Create, view, edit, archive managed plants; map-based placement with GPS and manual pin repositioning; persist captured GPS accuracy.
- Hierarchical, data-driven taxonomy; selectable/custom types, species, varieties; classification retained across rapid-entry workflow.
- Plant metadata: name, planting date/year, rootstock, nursery/source, notes, status, optional photos.
- Add Another Like This: keep place, classification, year, rootstock; clear unique name/location; allow quick GPS capture and save.
- Event timeline: planting, bud break, first/full bloom, petal fall, fruit set, prune, fertilize, spray, water, pest, disease, damage, harvest, death/removal, note/photo.
- Harvest events with quantity and unit; annual totals derived from events, grouped by unit (do not silently combine pounds and kilograms).
- Foraging resources: private by default, type, point/polygon, notes, observations/events, discovery date, optional photos.
- Filter/list/search by property/place, type/species/variety, planting year, item status and visibility; taxonomy parent filters include descendants.
- Tasks: create, list, complete, cancel; target item/place/category; due date and optional local reminder. Offline behavior must be documented and tested.
- Offline read and writes, restart durability, eventual synchronization using Firestore's mobile persistence, and cross-device verification instructions.
- Firestore security rules and tests, especially ownership and sharing visibility; no exact coordinates leaked for approximate-public records.
- Automated unit/widget/repository tests and a developer setup guide.

### 3.2 Later iterations (design for extension; not required to ship V1)

- Event-relative and recurring tasks (e.g. spray 10 days after full bloom).
- Routes/tracks while foraging, richer polygons and geospatial search.
- Public foraging discovery with server-side approximate-coordinate publication.
- Family/group membership, invitation lifecycle and advanced role management.
- Google Drive backup/import/export.
- Rich analytics, weather integrations, crop forecasting, advanced notification scheduling.
- Bulk import, web administration, desktop support.

**Important distinction:** The sharing model must be documented in V1; only ship sharing modes that can be enforced end-to-end by tested server rules. A public-approximate UI toggle is prohibited unless the backend publishes a separately sanitized coordinate and never exposes the exact coordinate.

## 4. Domain Model

The four conceptual pillars are **Things, Places, Events, and People/Permissions**.

### 4.1 Entities

| Entity | Key fields and relationships |
|---|---|
| AppUser | id, auth identities, display name, preferences, timestamps |
| Property | id, ownerId, name, description, optional boundary, default location, timestamps |
| Place | id, propertyId, parentPlaceId?, name, placeType, point/polygon geometry?, notes, timestamps |
| Taxon | id, parentId?, rank/type, commonName, scientificName?, sort order, built-in/custom ownership |
| TrackedItem | id, ownerId, propertyId, placeId?, taxonId, kind, name, description, geometry, GPS accuracy?, visibility, status, timestamps |
| ManagedPlant | item-specific plantedDate/year, rootstock, nursery/source, price?, replacementFor? |
| ForagingResource | item-specific firstDiscovered, landType?, accessNotes?, confidence? |
| Event | id, itemId, actorId, eventType, occurredAt, quantity?, unit?, notes?, photo references?, createdAt, updatedAt |
| Task | id, ownerId, title, description?, targetType, targetId, dueAt?, scheduleType, status, notificationLead?, recurrence/relative fields reserved |
| Photo | id, itemId, eventId?, storagePath, thumbnailPath?, caption?, takenAt?, capturedLocation?, uploaderId |
| Permission | id, resourceId, principalId, role, createdAt; OWNER determined by resource ownership |

Use client-generated UUIDs for user-created domain records; authenticated user identity is Firebase UID (do not invent mappings unless needed). Keep timestamps in UTC; display in local time. Event occurrence time and record creation time are distinct. Soft archive items rather than destructive delete by default.

### 4.2 Tracked item variants

`TrackedItem.kind` is `MANAGED_PLANT` or `FORAGING_RESOURCE`. Reuse map, event, photo, task and permission infrastructure. In Firestore, variant-specific fields may be embedded (`plant` / `foraging`) to avoid needless joins. Validate that the extension matches `kind`.

### 4.3 Geometry

Represent POINT as latitude/longitude and optional accuracy; POLYGON as ordered vertices with closure and basic validation. Plants use POINT. Places and foraging resources support POINT or POLYGON. No implicit precision upgrade from approximate GPS readings. Manual placement must be possible by dragging a pin or tapping a new map location.

### 4.4 Taxonomy

Data-driven parent/child tree, never hardcode all varieties in UI widgets. Seed at least:

- Fruit Tree → Apple → Honeycrisp, Zestar, Gala, Fuji; Peach, Pear, Plum, Cherry, Apricot.
- Berry → Blueberry, Raspberry, Blackberry, Strawberry, Gooseberry.
- Grape; Nut Tree; Vegetable.
- Mushroom → Morel, Oyster, Chanterelle, Chicken of the Woods.
- Wild Plant → Asparagus.
- Other.

Provide a Custom option for user-defined nodes. Taxon selection and filters must traverse descendants, so selecting Apple includes Honeycrisp and other varieties.

### 4.5 Event types and harvest

Define a typed event enumeration or validated registry: `PLANTED`, `BUD_BREAK`, `FIRST_BLOOM`, `FULL_BLOOM`, `PETAL_FALL`, `FRUIT_SET`, `PRUNED`, `FERTILIZED`, `SPRAYED`, `WATERED`, `PEST`, `DISEASE`, `DAMAGE`, `HARVEST`, `HARVEST_START`, `HARVEST_END`, `DIED`, `REMOVED`, `OBSERVATION`, `NOTE`, `PHOTO`.

Events are **append-oriented**. Permit corrections via an explicit edit/correction mechanism with audit metadata rather than quietly overwriting historical observations. For `HARVEST`, require positive quantity and explicit unit; derive annual totals from all valid harvest events for the item and year. Never persist a second authoritative yearly total. Group by unit; any conversions must be explicit and tested.

## 5. Technical Architecture

### 5.1 Technology decisions

- Flutter and Dart; Android-first, maintain iOS compatibility.
- Riverpod for state/dependency management; go_router for navigation.
- `google_maps_flutter` for maps and satellite imagery; platform-restricted Maps API keys, billing/API enablement required.
- Firebase Auth with Google Sign-In; Cloud Firestore for operational persistence and mobile offline cache; Cloud Storage for images; Cloud Functions only where server enforcement/sanitization is required.
- Location plugin with explicit permissions, timeout, denied/unavailable handling and manual map fallback.
- Local notifications for initial task reminders; do not imply guaranteed background execution across all devices.
- UUID identifiers, versioned serializable domain models, repository abstractions.

**ADR-001:** Use Firestore mobile offline persistence in V1, **not** a custom SQLite-to-Firebase sync engine. Validate that required offline queries are cache-backed and that offline writes survive process restart. Avoid Firestore web-only assumptions. Document limitations of initial offline use, auth expiry, conflict resolution and cache eviction.

### 5.2 Layering

```text
Presentation (screens, widgets, Riverpod state)
          ↓
Application (use cases, validation, filters)
          ↓
Domain (entities, value objects, repository contracts)
          ↓
Data (Firestore repositories, mappers, optional demo adapters)
          ↓
Firebase / Maps / Location / Storage / Notifications
```

Widgets must not directly query Firestore or reference collection paths. Domain objects must not depend on Firebase types. Keep mapping, serialization and validation in data/application layers. Provide an in-memory repository implementation for deterministic tests and a clearly marked demo mode if external configuration is missing.

### 5.3 Suggested repository layout

```text
README.md
pubspec.yaml
analysis_options.yaml
lib/
  main.dart
  app.dart
  core/{auth,location,maps,notifications,errors,utils}/
  domain/models/{app_user,property,place,taxon,tracked_item,event,task,photo,permission}.dart
  domain/repositories/{item_repository,event_repository,place_repository,taxonomy_repository,task_repository}.dart
  data/{firestore,mappers,seed,local_demo,repositories}/
  features/{authentication,map,plants,foraging,events,tasks,settings}/
test/{domain,data,features}/
firestore.rules
firestore.indexes.json
docs/{PRODUCT_REQUIREMENTS,ARCHITECTURE,DATA_MODEL,UI_UX,FIRESTORE_SCHEMA,SECURITY_AND_SHARING,OFFLINE_AND_SYNC,IMPLEMENTATION_PLAN,TEST_PLAN}.md
docs/adr/
.github/workflows/
```

Use actual valid Dart file names, not literal braces. Standard `flutter create` platform directories should be generated as appropriate; do not manually fabricate generated platform build artifacts.

### 5.4 Repository contracts

- `ItemRepository`: create, update, archive, get by ID, watch by property/place, filtered query, map bounds query or documented equivalent.
- `EventRepository`: append event, get/watch item history, optional correction, query by type/date.
- `PlaceRepository`: create/update, nested hierarchy, property lookup.
- `TaxonomyRepository`: seed/read tree, add custom taxon, descendant lookup.
- `TaskRepository`: create/update status, list by due window and target.

Support cancellation/disposal for subscriptions and deterministic error handling. Use a stable mapping of domain IDs to Firestore document IDs.

## 6. Firestore Model and Security

Proposed collections:

```text
/users/{uid}
/properties/{propertyId}
/places/{placeId}
/taxa/{taxonId}
/items/{itemId}
/items/{itemId}/events/{eventId}
/items/{itemId}/photos/{photoId}
/tasks/{taskId}
/shares/{shareId}
```

Illustrative item document:

```json
{
  "id": "uuid",
  "ownerId": "firebase-uid",
  "propertyId": "uuid",
  "placeId": "uuid",
  "kind": "MANAGED_PLANT",
  "taxonId": "honeycrisp-taxon-id",
  "name": "Honeycrisp #12",
  "geometry": {"type": "POINT", "lat": 42.0, "lng": -91.0},
  "accuracyMeters": 8.5,
  "plant": {"plantedYear": 2022, "rootstock": "M.111", "nursery": "Example"},
  "visibility": "PRIVATE",
  "status": "ACTIVE",
  "createdAt": "server timestamp",
  "updatedAt": "server timestamp"
}
```

Treat this as conceptual JSON; actual Firestore timestamps must be native timestamp values. Owner-based access must be enforced with Firestore security rules, not merely UI filters. Deny unauthenticated writes. Validate ownership of parent property/place and prevent clients from changing `ownerId` to steal records. Use strict authorization for nested events and photos; a contributor may add an observation only if granted permission. Firestore security rules are not query filters: design authorized queries and test them with the emulator.

### 6.1 Sharing model

Visibility states: `PRIVATE` (default), `SHARED`, `PUBLIC_APPROXIMATE`, `PUBLIC_EXACT`. Roles: `VIEWER`, `CONTRIBUTOR`, `MANAGER`, `OWNER`.

- Viewer: read permitted resources.
- Contributor: read and add events/observations to shared items, without changing ownership.
- Manager: manage item metadata and granted access within policy.
- Owner: full control, including ownership-sensitive operations.

Location ownership is separate from event authorship. Public approximate locations must be produced as **separate server-sanitized public records**; do not expose exact coordinates, hidden polygon vertices, GPS EXIF, private photo paths, or owner-private notes to anonymous readers. If this is not fully implemented/tested, V1 UI must expose only PRIVATE and safe SHARED flows, with public modes disabled and clearly labeled as future functionality. For V1, private-only is acceptable until secure ACL support is complete; document the gap.

### 6.2 Indexes, queries and privacy

Document required composite indexes for property, place, kind, status, dates, and filtered lists. Firestore has limitations for geospatial bounds and taxonomy-descendant queries: choose a pragmatic V1 approach (e.g. property-scoped bounded queries + client-side filter with documented scalability constraints, or geohash indexing), and avoid global unrestricted downloads. Enforce per-user access in all queries.

## 7. UX Specification

### 7.1 Home map

Default satellite/hybrid map, GPS/current-location button, tappable markers, filter action, floating Add button, bottom navigation `Map / Plants / Tasks` (Foraging reachable from add/filter or a dedicated navigation destination if more usable). Distinguish managed plants and foraging resources visually; include list fallback when map unavailable.

### 7.2 Add menu

Actions: `Plant`, `Foraging Location`, `Task`, `Record Activity`. New plant form fields: property/place, type → species → variety, custom option, name, planted date/year, rootstock, nursery/source, notes, photo, GPS/manual map pin. `Save` and `Save & Add Another`/`Add Another Like This`. Validate required values and show clear offline save state.

### 7.3 Plant detail

Photo/placeholder, classification breadcrumb, property/place, planting metadata, mini-map/location, status, year-specific harvest totals, recent activity, tabs or sections `Overview / History / Tasks`. Buttons `Record Activity`, `Edit`, `Add Another Like This`. Handle missing photos and historical data gracefully.

### 7.4 Record activity

Type picker with bloom, harvest, spray, fertilizer, prune, pest/disease, watering, photo and note. Dynamic form by event type; harvest requires date, quantity, unit, optional quality/notes/photo. Save offline and show in timeline immediately. Show actor and event time for shared resources.

### 7.5 Foraging

Foraging map/list with type filters and `Mine / Shared / Public` visibility filtering only for supported sharing modes. Resource detail: point/area, discovered date, observation timeline, photos, access notes, sharing. Private is default; require confirmation before broader disclosure.

### 7.6 Tasks and filters

Tasks screen: `Today / This Week / Upcoming`, status and target. Filter sheet: source, place, plant type, species, variety, planted year, status and visibility. Parent taxonomy filter includes descendants. Preserve filter state during navigation when practical.

## 8. Offline, Sync, and Conflict Behavior

- After initial sign-in/configuration, core records and previously loaded map data remain usable without network.
- New plants/events/tasks can be created while offline, persist across app restarts, and synchronize on reconnection.
- Provide meaningful pending-sync/error indicators where technically feasible. Never say “synced” when only locally queued.
- Events use unique IDs and append operations to minimize conflicts. Mutable metadata: document a deterministic last-update-wins approach for V1 and surface potential overwrite limitations; no silent loss of harvest events.
- Handle auth failures, permission revocations, storage upload retries, and missing offline map tiles separately. **Google satellite map imagery is not guaranteed offline** merely because Firestore caches records; use a list fallback and cached marker data when map tiles are unavailable.
- Image uploads may be deferred while offline; do not promise Storage SDK automatically queues uploads durably without implementing a local upload queue.

## 9. Acceptance Tests

1. Launch app with configured Firebase; sign in; create property and nested place.
2. View satellite map, request GPS permission, see position, deny permission and still manually place a marker.
3. Add `Honeycrisp #12` under Fruit Tree → Apple → Honeycrisp, planted 2022, rootstock M.111; marker appears and survives restart.
4. Use Add Another Like This; taxonomy/place/year/rootstock retained, name and coordinates cleared; save distinct second tree.
5. Record full bloom and harvest `13.1 lb`; timeline and yearly harvest total show 13.1 lb.
6. Record another 2.4 lb harvest in same year; total becomes 15.5 lb. Different units remain separate unless explicit conversion exists.
7. Enable airplane mode; create an event and plant; force-close/reopen; both persist; reconnect; verify eventual appearance on another authenticated device.
8. Add private morel patch as point or polygon; add observation; private by default.
9. Filter Apple and see Honeycrisp descendants; filter planting year and place correctly.
10. Create a task targeted at a plant; complete it; verify status persists.
11. Verify unauthenticated users and another unrelated user cannot read or write private records through Firestore emulator tests.
12. Verify public approximate records (if enabled) never reveal exact coordinates through any exposed document, image metadata, or read path.
13. Run `flutter analyze`, `flutter test`, and build checks where environment allows; report exact results and limitations.

## 10. Delivery Sequence

**Phase A — Documentation (first, separate commit):** Populate all `/docs` files and ADRs. Link them from README. Record V1 versus future features, assumptions, risks and test plan. Do not start implementation until docs are committed.

**Phase B — Foundation:** Initialize Flutter project, app theme, routing, Riverpod, domain models, validation, repository interfaces, in-memory/demo implementations, taxonomy seed, unit tests and CI. Ensure project can launch in demo mode without secrets.

**Phase C — Core plant slice:** Property/place CRUD, map/GPS/manual pin, Add Plant, taxonomy, markers, plant detail, rapid entry, events and harvest totals; widget and domain tests.

**Phase D — Persistence and authentication:** Firebase Auth, Firestore mapping, security rules and emulator tests, offline persistence, sync state/error handling, second-device procedure. Protect private records.

**Phase E — V1 completion:** Foraging points/polygons, tasks/local notifications, filters, photos with documented offline upload handling, UI polish, regression tests, setup docs and release checklist. Implement sharing only to the level securely supported by rules/tests.

Open PR(s) with meaningful summaries, screenshots if feasible, changed-file list, tests run, setup still required and known limitations. Do not merge automatically. If the work exceeds one practical PR, open a documentation PR first, then implementation PR(s) based on merged docs or clearly identify dependency.

## 11. Developer Setup and CI

Document Flutter SDK version constraints and commands for `flutter pub get`, `flutter analyze`, `flutter test`, and Android build. Use FlutterFire CLI/configuration as appropriate, but **never commit secrets or local signing keys**. Provide Firebase project setup, Android/iOS app registration, SHA fingerprints/Google sign-in requirements, Maps SDK enablement, API-key restrictions, Firestore/Storage rules deployment, emulator test steps, and iOS permissions/plist instructions. Do not commit unreviewed permissive Firestore rules. Add GitHub Actions for static analysis and tests using a pinned/supported Flutter version. Clearly identify what can and cannot be validated without developer-provided credentials or device hardware.

## 12. Risks and Open Design Choices

- Maps satellite tiles are not an offline basemap guarantee; provide fallback.
- Firestore offline query cache may be incomplete for data never previously loaded.
- Fine-grained sharing rules and public approximate discovery require deliberate server-side design; defer unsafe modes.
- Large property and nationwide public geo-query scaling may require geohashes or backend search later.
- Mobile location accuracy varies; manual pin adjustment is essential.
- Photos require an explicit offline upload/retry strategy.
- Cross-device sync and sign-in require external Firebase configuration and real-device validation.
- Taxonomy seed identifiers should be stable across clients; custom taxa need owner scoping.
- Event edits/corrections should preserve auditability; choose an explicit policy and test it.

## 13. Definition of Done

V1 is done when the required acceptance tests pass, the app is runnable on Android with documented Firebase/Maps setup, works for core operations offline after initial provisioning, persists and syncs safely, enforces private-record access, supports plant and foraging entry, event/harvest history, basic tasks, filtering and rapid orchard entry, and has useful documentation and reproducible tests. Features requiring external configuration must be labeled **not yet validated** until exercised; a UI-only mock is not sufficient evidence of backend synchronization.
