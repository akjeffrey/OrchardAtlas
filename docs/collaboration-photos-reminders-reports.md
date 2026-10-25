# Sharing, field media, reminders and reports

## Availability

The Android local-data build supports Plant Detail → Show on Map, task editing and
local notifications, foraging resources/observations, camera/gallery photos,
harvest reports, and activity revision recovery. Its existing Drive file backup
includes the new records and image bytes. An update uses the existing package ID
and permanent signing key; no reinstall or migration is required.

Invitations, editor/viewer collaboration, public resource discovery and Firebase
Storage uploads require the connected build and a configured Firebase project.
The local-data APK does not silently transfer local orchards into Firebase.
Settings → Orchard sharing explains the distinction. Drive file sharing continues
to use Google Drive permissions; it is not the same as collaborative app roles.

## Tasks and reminders (#24)

Use a task's edit icon, or Edit task & reminders on a group checklist. Update its
title, notes, linked completion activity, harvest quantity and one-time due date.
Changes affect open work in the current occurrence and the definition used for
future work. Completed, skipped and cancelled members, original target IDs,
completion dates and linked activities remain unchanged. Targets and recurrence
anchors are fixed; create another task to change them. An optional `anchorOn`
field keeps one-time checklist member UUIDs stable when its due date changes.

Choose a reminder on the due date or 1/3/7 days beforehand at 9 AM local time.
Notification permission is requested when reminders are enabled. Undated tasks
do not notify. One notification aggregates open members per occurrence. Closing
work or changing a reminder reschedules alarms. The app schedules upcoming known
and predicted recurring work for 30 days, up to 60 reminders per orchard. Reopen
it to refresh that horizon, timezone changes and newly matching plants. Android
alarms survive process closure, device reboot and in-place APK replacement;
inexact alarms may be delayed by battery restrictions. iOS uses local scheduled
notifications and its system-wide pending-notification limit. Reminders are not a
background synchronization service.

## Sharing (#26)

The owner invites an email as viewer or editor in Settings → Orchard sharing.
The recipient signs into that account, verifies their email, refreshes their
session and accepts the invitation. New registrations send a verification email.
Accepting atomically creates the membership and a private user-orchard directory
link and consumes the invitation. Invitations cannot grant ownership. The owner
can revoke members; content editors cannot manage membership or rename orchards.
A revoked directory link is harmless: every orchard read is checked independently.
Viewers can read; editors can modify orchard content. Rules are authoritative,
including for requests bypassing the UI. Viewer mode labels the orchard and disables
common editing controls. Signing out cancels scheduled notifications. Offline cached data cannot be remotely
erased; sign out and clear cache on shared phones. Revocation takes effect on
server access; queued writes are rejected if access has been removed.

Deploy `firestore.rules` and `storage.rules` to the intended Firebase project
before testing sharing. Keep email/password Authentication enabled, verify
Storage bucket configuration, and permit Firestore access from Storage rules.
Use two test accounts to validate invitation, viewer, editor and revocation flows.
No service account, signing secret or Maps key is stored in source.

## Foraging (#27)

Settings → Foraging resources supports resource entry/editing, shared taxonomy,
GPS or a picked map location, a month range (including seasons crossing New Year),
private notes, dated observations and photos. The resource detail map shows its
position. Foraging records are separate from managed planting and do not join
plant task checklists or harvest reports implicitly.

Public listing is an explicit opt-in. In connected mode its write is atomic with
a sanitized `publicResources/{orchardId}_{resourceId}` projection. Only name,
classification, exact coordinates and season are exposed to signed-in discovery;
private notes, observations, orchard memberships and media are excluded. Turning
publication off deletes the projection. Browse public resources displays up to
200 listings and their map locations. In the local build the preference is saved
but nothing is published externally.

## Photos (#28)

Plant and resource details offer camera or gallery selection. Native adapters
resize/re-encode JPEGs to at most 1280 pixels and 512 KiB, with 160-pixel thumbnails
bounded to 32 KiB; encoded files omit original EXIF metadata. Cancel leaves no
record. No broad Android storage permission is requested. iOS prompts for camera
or photo-library permission.

Local photos are included in orchard snapshots and the existing 20 MiB backup
limit. Connected photos are first submitted to the Firestore offline cache with
their source bytes and thumbnail. A serialized application worker uploads pending
JPEGs to `properties/{orchard}/items/{item}/photos/{photo}.jpg`. Source bytes are
cleared only after upload success; failures keep them pending with a visible
message, retry on the minute timer and retry after restart. Uploads run while the
app is active, not after force-stop. Object writes are idempotent by photo UUID.
The full-size uploaded image is read through authenticated Storage, while its
thumbnail remains available in Firestore offline cache. Delete removes its file
and metadata; plant/section deletion includes associated photo and revision data.

## Harvest reporting and activity recovery (#29)

Settings → Harvest reports & recovery combines managed-plant harvest events and
seasonal crop harvests. Filter by year and Group/Type/Variety and group by month
or plant label. Mass converts to kg; whole counts are kept separately. Copy CSV
exports the filtered source records, original units and source IDs. Historical
and archived planting records are included; permanently deleted records are not.

Editing/deleting an activity retains an immutable prior snapshot in the orchard's
activityRevision collection, atomically with the mutation. Firestore rules require
the snapshot to match the original event and deny rewriting revisions. The
recovery screen shows these snapshots and asks before replacing an activity.
Existing activities preserve identity and attribution. Restoring a deleted event
attributes its recreation to the restoring account; original attribution remains
in the revision. Restoring a deleted task-generated event also completes its
linked task. Revisions cannot recover permanently deleted plants and are removed
with permanent deletion. Crop harvests remain append-only; this revision workflow
covers editable plant activities. This is user-level recovery, not an external
compliance audit log.

## Plant Detail map navigation (#69)

Show on Map reuses Edit Plant's saved-location focus route. It centers the active
plant, temporarily reveals it when grouped, and selects the anchored name label.
Back returns to Plant Detail. Archived plants must be restored first.

## Verification

CI runs domain, mapping/local persistence/backup, photo retry, reminder grouping,
task identity, yield and widget regressions, Firestore emulator rules tests,
Android/iOS native compilation and signed APK identity verification. On phones,
exercise permission denial, picker cancellation, reboot/update alarms, airplane
mode photo entry/restart, backup restore with photos, and two-account sharing.
