# Offline-first behavior

## Contract
After online setup and initial data loading, native Firestore persistence stores
plants and activities across process restarts. UUIDs are generated locally.
Snapshots include metadata changes so UI can show “Cached data” and “Pending sync”.
Offline queries only include downloaded records; a cached empty collection does
not establish there are no remote records. Initial online sync is required for
account creation and discovery on a new/reinstalled device.

Known default properties are read explicitly from the native cache first, so an
offline restart does not wait for a server timeout. A cache miss falls back to a
server read; first-time setup still requires connectivity. Data streams continue
to enforce authorization on reconnection.

## Write lifecycle
1. Validate domain input and allocate one UUID.
2. Submit set to native Firestore; return control without awaiting server ACK.
3. Local snapshot immediately renders plant/marker/activity/totals.
4. Pending metadata remains until reconnection and server authorization.
5. Observe the write future for errors; publish rejected record IDs to UI.

The command returns “Saved locally”, never “Synced”. Write futures can remain
pending indefinitely offline. Do not hold forms/loading spinners until they resolve.
No custom queue competes with Firestore's queue. The timestamp reflects the user's
selected activity date and device clock, not server arrival time.

## Conflicts, retries and limitations
Different event UUIDs preserve concurrent activities. Concurrent edits to the same
plant use Firestore last-write-wins; V1 only creates plants, limiting that risk.
Rules disallow event edits/deletes; future correction events need a new design.
A duplicate save retry uses its existing ID. The app blocks rapid duplicate taps.
If a write is rejected after reconnect, native snapshots may roll back; show a
warning and ask the user to record it again once authorized. A custom persistent
rejection recovery queue is deferred; errors from a killed process may not be
available on the next launch, so pending status is not a delivery guarantee.

Google Maps tile caching is provider controlled and cannot be promised. The list,
manual coordinates, cached taxonomy and details remain usable without tiles. GPS
can work without Internet but signal quality varies. Firebase Auth needs network
for new sign-ins; persisted sessions support offline use. Photos require a future
file queue with explicit upload state; Storage alone is not offline persistence.

## Manual release scenario
Sign in online; add a plant and harvest; wait until pending clears. Disable network;
add a second plant and two harvests; verify marker, activity history and annual
mass/count totals; force-stop/restart offline; verify records persist. Reconnect
and check pending clears and a second device sees records. Also revoke access
while disconnected and observe rejection on reconnection. Sign out and verify a
second account cannot see the first account's cached records.

## Custom taxonomy and planting dates

Property taxonomy uses a repository stream, including Firestore's persistent local cache. Newly submitted taxa are immediately available to the form; asynchronous cloud rejection appears through the existing write-failure banner. Trial mode stores custom taxa and their symbol IDs in the same JSON document as plants and events. The optional `taxa` array defaults to empty when reading older trial saves, preserving existing plants and harvest records. Plant plus planting activity is one serialized trial write or one Firestore batch. Dates remain calendar dates rather than being re-derived from UTC timestamps.


Trial 0.2 extends the same JSON snapshot with optional metadata and a tasks array. Older saves default missing fields and recover missing planting-date metadata from the original planting activity. Metadata edits, archives and task status changes use the serialized write queue, survive repository restart, and feed the same pending/error indicators. Firestore counterparts use native persistent cache-backed streams and queued writes. Concurrent edits to mutable metadata/task status use last-submission-wins semantics; there is no custom conflict merge or notification scheduler. Events remain separate append-only records.

Trial 0.3 stores sections, seasonal crops and append-only crop harvests in optional arrays in the existing JSON snapshot. Group checklist creation validates every target before one local snapshot write; member status edits rewrite only the relevant member in memory before the serialized snapshot is persisted. Firestore groups use one write batch (up to 400 members), while later member edits are independent so one person's partial progress does not overwrite every member. Geometry/crop-completion metadata still uses last-write-wins. A new crop season never updates the earlier record. Shared editing, notifications, durable photo queues and public data remain outside this increment.
