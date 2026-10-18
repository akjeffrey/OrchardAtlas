# Firestore schema (version 1)

Trial 0.6 extends the foundation schema below; the current rules and release
addendum at the end supersede the initial append-only and reserved-task policies.

All records include `schemaVersion: 1`. Document IDs are UUID strings except user
and membership IDs. Native Timestamp and GeoPoint stay in data mappers only.

```text
properties/{propertyId}
  schemaVersion, name, ownerId, createdAt: Timestamp
  members/{uid}                         # future owner-managed sharing
    role: editor|viewer
  items/{itemId}
    schemaVersion, kind: managedPlant|foragingResource,
    name, taxonId, location: GeoPoint, createdAt: Timestamp
    events/{eventId}
      schemaVersion, authorId, type, occurredAt: Timestamp,
      activityDate: YYYY-MM-DD, recordedAt: Timestamp,
      notes: string, harvest: {quantity: number, unit: kg|g|lb|count}?
  tasks/{taskId}                         # reserved, denied in V1
  photos/{photoId}                       # reserved, denied in V1
users/{uid}                             # reserved, denied in V1
```

Property/item IDs come from paths and are supplied to mappers, not duplicated in
child payloads. Taxonomy is local V1 data; a future `taxa/{taxonId}` collection is
read-only to clients and needs catalog versioning. Storage paths are
`properties/{propertyId}/items/{itemId}/photos/{photoId}`.

## Queries and indexes
Default-property discovery queries `properties` where ownerId=uid (single-field
index), then sorts deterministically client-side. Plant map subscribes to all
`items` in the selected property; events stream all documents under an item and
sorts by activity date then recordedAt. No composite indexes required for V1.
Scale-up: paginate activity history, query activity year, and spatially partition
items with geohash. Index changes must accompany each new query.

## Mapping and migration
Reject unsupported schema versions and invalid payloads with actionable stream
errors rather than silently dropping records. Domain constructors validate ranges,
units, dates and names. Unknown event types must trigger an error until a reader
upgrade is available. Client clocks supply occurred/recorded times so records can
be created offline; these are observations, not trusted audit/security timestamps.
A future additive migration retains old readers or bumps schema version explicitly.

## Rules
V1 private owner access is evaluated at the property path. Member administration
and access are deferred; the reserved membership path grants no access in V1.
Owner-only property creation, fixed owner/creation identity, strict allowed keys,
field types/ranges and enum validation. Item identity and creation date are stable.
Events allow create/read only; author must match authenticated UID. Rules enforce
harvest payload structure, positivity and unit even if a client is compromised.
V1 denies member administration and all reserved collections. Sharing roles are
specified for future work; no invitation UI or public rule is shipped.

## Property-specific taxonomy additions

`properties/{propertyId}/taxa/{taxonId}` stores append-only custom catalog options: `schemaVersion: 1`, `name: string (1–500 characters)`, `rank: group|genus|species|cultivar`, `parentId: UUID|null`, and `symbol: tree|apple|pear|berry|flower|citrus|nut|vine`. Group parents are null; other ranks require a parent UUID. IDs of curated starter taxa remain stable. The application merges starter and property taxa and validates complete, consecutive ancestry before accepting an addition. Rules enforce ownership, UUID paths, field types, supported ranks/icons, and immutability; hierarchy integrity against the bundled starter catalog is an application validation.

A plant and its optional planting event are committed in one Firestore write batch. Event rules use `getAfter` to accept a parent plant created by the same batch, while rejecting events without a plant. Existing event author, quantity, and append-only protections continue to apply. No plant schema migration is required.


## Plant management and tasks (ADR-002)

Managed-plant documents accept optional `plantedOn` (YYYY-MM-DD or null), `rootstock` and `nursery` (strings up to 500 characters), `notes` (up to 10,000), `status` (active/archived) and `accuracyMeters` (finite number 0–100,000 or null). Read defaults preserve schemaVersion 1 compatibility. Metadata updates may change only name, rootstock, nursery, notes and status. Captured identity, taxonomy, location, accuracy and planting date remain immutable through this editor. Events stay append-only.

`properties/{propertyId}/tasks/{taskId}` stores `schemaVersion: 1`, `title`, `notes`, `itemId: UUID|null`, `dueDate: YYYY-MM-DD|null`, `status: open|completed|cancelled` and native Timestamp `createdAt`. Ownership is inherited from the property; an item target must exist under that same property. Only status can change after creation; delete is denied. Domain validation rejects invalid calendar dates; rules validate date shape. Tests exercise anonymous/foreign-owner denial, targets, immutable fields, invalid values, status changes and reopening.

Queries remain property-scoped collection streams backed by Firestore's local cache. Plant/task filters run on those records on the client; no additional composite indexes or global downloads are required. This is intended for ordinary personal orchards, not a nationwide resource search; cache completeness and large-property scale remain documented limits. Deploy the updated rules before trying these connected-mode features.

## Layout, seasons and group checklists (ADR-003)

All new records live under `properties/{propertyId}` and remain owner-only. `sections/{id}` contains schemaVersion, name, kind (area/bed/row), parentId, notes, createdAt Timestamp and a list of native GeoPoint vertices. The domain validates simple polygon topology, distinct vertices and consecutive hierarchy; rules enforce coordinate type/count, parent kind/scope and immutable parent/creation/kind. Geometry/name/notes updates use last-write-wins. Plant `sectionId` is optional and assignable only to a section in the same property.

`crops/{id}` contains schemaVersion, sectionId, taxonId, label, season, notes, plantedOn, harvestedOn, status and createdAt. Creation is growing; only status/harvestedOn may subsequently change. Ended crops cannot reopen. A new season creates a new record. `cropHarvests/{id}` contains schemaVersion, cropId, activityDate, notes, recordedAt and positive quantity/unit harvest data; it is append-only. Calendar strings remain independent of UTC record timestamps. Crops/harvests preserve original units.

Task documents optionally add sectionId, cropId, groupId, groupScope and completedOn. Exactly one explicit target (plant/section/crop) or a whole-property task is allowed. Skipped is a supported status; completedOn is optional for legacy compatibility and only valid with completed status. Updates may change only status/completedOn. Group members share a UUID groupId and are created in one batch, then written independently. Group progress is derived from member tasks, not another stored total. To support up to 400 members without exceeding Firestore's batch rule document-access limit, group membership references are validated against property-scoped plant/section/crop snapshots by the application; rules validate UUID/owner scope and immutable member identity but do not perform individual existence lookups for grouped members. Such references never grant read access to another property. Direct tasks retain existence checks. This distinction is tested with a 25-distinct-plant batch and documented in ADR-003.

Streams remain property-scoped with client-side descendant/status filters; no extra composite indexes are required. Cached queries can be incomplete, as in previous increments. Deploy the new rules before using the connected build.

## Trial 0.6 addendum

`properties/{propertyId}/taskPlans/{planId}` stores title, notes, createdAt, target
(plant/plants/section/sections/crop/crops/property), optional itemId, sectionId,
cropId, taxonId, sectionKind, dueDate, repeat (none/daily/weekly/monthly/yearly),
eventType and eventHarvest. Zero matching records are valid for group criteria.

Tasks add planId, occurrenceOn, eventType and eventHarvest to existing immutable
target metadata. Assignment IDs are deterministic UUID5s of plan/occurrence/target.
Completion updates status/completedOn. Linked events add taskId and use a stable
UUID5 of that task ID. Completion/reopening batches the task with the event mutation.
Event editors preserve authorId, recordedAt and taskId; owners may correct other
fields or delete activities. Harvest totals always derive from current events.

Sections add ARGB integer color and nullable supported-symbol name. Canonical kinds
are area and row; compatibility readers map legacy bed to area. The first/last row
vertices define start/finish. Managed plants add optional nonnegative rowOrder, and
permit edits to classification, location, plantedOn, section assignment and accuracy.
Identity/createdAt remain stable. No duplicate taxonomy migration is needed: old
cultivar IDs are surfaced as Variety choices.

All operations remain owner scoped. Permanent deletion enumerates server children
and references before deleting parents, including item photo metadata and known
Storage paths. It requires connectivity, is retryable, and is not a multi-device
transaction. See release-0.6.md for operational limits.

## Classification edits and small icon assets

Per-property `taxa/{taxonId}` documents can override starter catalog IDs for that
orchard. Name, symbol and optional `customIconId`, `iconOverride` and scientific
name metadata may update; rank and parentId remain immutable. The domain merges
these records over the starter catalog, preserving plant/event/task references.
`iconOverride` is nullable for compatibility: curated defaults inherit user-edited
ancestor icons, while older user-created options keep their explicit icon choices.

`properties/{propertyId}/icons/{iconId}` stores `{schemaVersion: 1, name, png}`. `png`
is bounded base64 of a normalized PNG (≤32 KB, ≤96×96 pixels). Readers validate PNG
chunk integrity and dimensions. Icons are owner-only under the current ACL, with
immutable image payloads; deletion is disabled to protect references. New images
use UUIDs. Taxa and sections can reference icons only within their property.
Section updates allow optional `customIconId` in addition to existing symbol/color.

The Android trial embeds the same asset mappings inside its orchard snapshot,
which existing backup/export/restore includes without relying on external file
paths. Firestore caches these small self-contained documents through its existing
offline persistence. Deploy the updated Firestore rules before using the connected
backend with these fields; local trial APKs do not require a Firebase deployment.


### Deleted custom icons

Icon deletion is an owner-only, irreversible update to `{schemaVersion: 1, name: 'Deleted icon', png: '', deleted: true}`. It removes image bytes while retaining the UUID for existing and delayed offline references; physical document deletion and tombstone resurrection are denied. Readers accept legacy image records without `deleted`. Library/picker choices exclude tombstones, but assignments continue to resolve to an explicit **question mark**, including inherited taxon icons and optional Area/Row icons. Tombstones persist in local snapshots and backups and do not count toward the 128 active-image limit. Plant data and history are untouched. `unknown` is the built-in question-mark symbol; normal icon size tiers also apply to it.
