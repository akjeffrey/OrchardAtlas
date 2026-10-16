# Satellite map and map entry

The phone trial and Firebase mode use the same Google Maps satellite widget.
Firebase setup is independent of map setup. Native startup reports whether a Maps
key is configured; the key never crosses the Flutter method channel. Without a
key the app explicitly labels its coordinate sketch, allowing records to remain
accessible without trying to construct an unconfigured iOS map.

Data mode retains status, plant filtering and tabs above a partial map. Full-screen
mode hides those data controls. Switching modes preserves the map controller,
camera, selection, filters and unsaved geometry. Android Back first exits map mode;
leaving a nonempty drawing requires confirmation. The native map owns its controller.

Add row / Add area starts a draft directly on the map. Tap vertices in order, undo
the last vertex or drag a pin. Finish validates the existing domain geometry rules
(2–40 line vertices, 3–40 polygon vertices, distinct points, no self-intersection),
then collects a name and optional parent area/bed. Drafts never enter storage until
saved; saved sections use the existing repository and offline persistence. Existing
sections provide spatial context and remain visible while drawing. Saved shapes
open their detail on tap and can be edited through the existing section editor.

Search is separate from the plant filter. Decimal latitude/longitude is validated
locally and works offline. Addresses use an AddressSearchRepository backed by
Android Geocoder or iOS CLGeocoder through a small platform channel. Show up to five
results for explicit selection, and report unavailable/empty lookup without moving
the map. No Places or Google Geocoding REST key, autocomplete billing or Firebase
connection is required. Device geocoders can require network and impose throttles.
Searching or centering GPS during drawing changes the camera without adding a vertex.

Google imagery is network dependent. We do not promise downloadable satellite maps,
prefetch tiles or persist geocoder results. Drawing/records and numeric search do
not depend on map tiles: coordinate entry and the Plants tab remain available.

Google Maps SDK mobile map loads currently have unlimited free usage, including
satellite view. A billing-enabled Google Cloud project and restricted platform API
key are still required. Other APIs have separate prices. See Google's current
[pricing](https://developers.google.com/maps/billing-and-pricing/pricing).
