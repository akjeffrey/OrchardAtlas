# Firestore schema (version 1)

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
Private owner access and member reads/writes are evaluated at the property path.
Owner-only property creation, fixed owner/creation identity, strict allowed keys,
field types/ranges and enum validation. Item identity and creation date are stable.
Events allow create/read only; author must match authenticated UID. Rules enforce
harvest payload structure, positivity and unit even if a client is compromised.
V1 denies member administration and all reserved collections. Sharing roles are
specified for future work; no invitation UI or public rule is shipped.
