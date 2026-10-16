# Multiple orchards and saved map views

Each Place is one orchard, owned by one user. Selection is saved per user on this
device. Existing single-orchard data keeps its identifiers and is never reassigned.
Firestore continues to use properties/{orchardId}/... and owner-filtered property
queries; private owner rules apply independently to every orchard. Trial storage
retains the original JSON snapshot and adds a catalog plus independent snapshots
for additional orchards. Directory operations have their own domain interface.

All plant/event/task/section/crop/taxonomy streams follow the selected Place.
Switching clears submitted taxonomy, filters and map state, and recreates screens
under a key for that orchard, preventing prior async stream values from appearing
under the next orchard's name. Selection is only available on the home map; active
forms retain their orchard. Switching a nonempty drawing requires discard approval.

Default views are device preferences scoped by user and orchard: latitude,
longitude, zoom, bearing, tilt and full-screen/data mode. Save requires an actual
camera position; the initial world overview is not a captured orchard position.
User settings go through a repository interface; widgets contain no preferences
or Firebase storage logic. Explicit saved-plant focus wins over a saved default.

Map drawing retains the existing native map and complete camera. A visible Back to
map action and Android Back cancel/discard drawing and return to the prior display
mode. Saving a shape also returns to that mode. The separate section editor accepts
the current map view as an initial value; it must not overwrite it with automatic
GPS or force a zoom of 19. The map owns its controller lifecycle.
