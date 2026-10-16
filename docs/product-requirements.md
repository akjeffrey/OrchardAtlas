# Product requirements

## Purpose and users
OrchardAtlas is a Flutter Android/iOS field notebook for orchard growers, gardeners,
and people tracking foraging resources. It connects physical locations to plant
identity and a durable history of care and yield. A grower walking a row should
record successive trees with minimal typing; a gardener should see what happened
to a plant over successive seasons. Precise foraging coordinates are private.

## V1 scope and acceptance criteria
- Authenticate with Firebase email/password; a returning authenticated user can use
  cached data without a network. Registration requires connectivity.
- Create one private default Property/Place for each account. Display its plants
  on Google Maps. Multi-property selection is a later increment.
- Request foreground GPS only after a user action. Handle disabled services,
  denied permission, permanent denial, timeout, and poor accuracy. Let the user
  move the map pin if GPS is unavailable or unsuitable.
- Add a managed plant at a GPS or manually selected coordinate. Select a hierarchical
  taxonomy (group → genus → species → optional cultivar), with stable UUID IDs.
  V1 ships a small starter catalog and supports property-specific additions with map symbols.
- Save a plant locally through Firestore persistence and show its marker. Open
  the plant detail through the marker or plant list.
- Record dated activities: planting, bloom, pruning, fertilizing, spraying,
  pests/disease, watering, harvest, removal, note, and photo reference.
  V1 implements textual activities and harvest; capturing/uploading photos is
  deferred, with a Storage repository boundary and schema reserved.
- Record harvest as positive quantity plus explicit unit (kg, g, lb, count).
  Derive totals for the selected calendar year from events. Display each recorded unit separately;
  display count separately. Never silently combine count with mass.
- “Add Another Like This” copies taxon and name into a new form but requires a
  fresh GPS location (or manual coordinates) and new UUID. Never copy events or plant identity.
- Offline after a successful online sign-in: browse cached plants/events, save
  plants, append events, see local totals, restart and recover those records.
  Show local/pending versus server-confirmed data and rejected-write errors.

## Non-goals for this slice
Invitations and shared editing UI, public foraging discovery, polygon drawing,
bulk imports, taxonomic catalog administration, reminders, push notifications,
photo capture/upload queues, pesticide compliance advice, and analytics backends.
Tasks and foraging resources are modeled but do not have V1 CRUD screens.

## Product constraints
Coordinates, account details, and photos are sensitive. No public access by default.
No background location tracking. No Firebase SDK in widgets or domain entities.
No committed API keys, project configuration, signing material, or credentials.
Maps tiles are not guaranteed offline; cached records and a plant list remain useful.
The app is a recordkeeping tool; identification is not an edibility guarantee.

## Success and verification
Verify the full GPS → taxonomy → marker → detail → harvest workflow on Android and
iOS, then repeat after disabling network and restarting the app. Domain tests cover
calendar boundaries and unit conversions; mapper tests prove schema round trips;
emulator tests verify private access and immutable activities. Deployment needs a
real developer Firebase/Maps project and physical-device checks, not just unit tests.


The next trial increment in [ADR-002](adr/002-trial-management.md) adds planting-date defaults/inheritance, metadata editing, soft archive, search/classification/year/status filters, basic due-date tasks and expanded phenology events. These are usable in local trial mode with corresponding Firestore adapters/rules; nested places, foraging geometry, photos, notification scheduling and sharing remain future increments.
