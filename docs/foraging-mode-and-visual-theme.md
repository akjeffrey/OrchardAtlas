# Foraging mode and the OrchardAtlas visual theme

## Mode navigation

Use the **Switch mode or orchard** arrows in the home app bar. The **Mode &
orchard** picker offers Foraging and the existing orchard list. The existing
Orchard options → Select orchard entry opens the same picker.

- Choosing **Foraging** opens its own resource map, resource list and Add Resource
  flow. Orchard plants, row/area drawing and plant tasks are not shown there.
- Choosing an orchard returns to orchard mode with that orchard selected. Existing
  orchard creation/rename and map defaults remain available.
- Mode choice is remembered on this device per signed-in account, independently
  of orchard map preferences. Older installations default to orchard mode. The
  preference also travels with local backups and is reloaded after restore.
- Foraging resources retain their current orchard association and permissions.
  The foraging header identifies that context. There is no migration, merge,
  duplication or widening of resource visibility when switching views.
- Explicit plant Show on Map navigation still opens the orchard map even from a
  foraging session; Back returns to the previous page and leaves the remembered
  mode intact.

Foraging mode includes satellite/sketch map support, GPS recentering, location
search, full-screen/data mode, and a list. Resource markers retain the existing
first-tap name / second-tap detail behavior. Tap the map to drop a draggable pin. Add Resource uses that selected point even
if the camera is panned, searched or recentered afterwards. With no pin it falls
back to the current map center when available. Cancelling entry retains the pin;
saving a new resource clears it. Clear selected location removes it explicitly. Public discovery remains available in connected
mode. Removing the old Settings → Foraging resources shortcut makes the mode
switcher the primary entry point; existing resource details, observations and
photos keep their storage paths and identities.

## Shared visual language

The supplied app icon is the source of the palette: forest green `#19492D`, leaf
green `#507A32`, warm ivory `#F7F4E9`, and apple red `#BB2D27`. Green is used for
navigation and primary actions; red remains an accent and is associated with
attention/destructive states. Text uses a dark green ink color with contrasting
white button labels. The original icon is reused in the switcher, foraging home
and sign-in screen; no replacement icon is generated.

`orchardTheme()` applies the palette, rounded outlined inputs, white fields,
button sizes, cards, dialogs, selection controls, app bars and snackbars across
all screens. `OrchardForm` adds consistent field spacing and a maximum 720-pixel
form width while retaining vertical scrolling, labels, validation, controller
state and save behavior. The planting, plant editing, activity/harvest, seasonal
planting, task editing/creation, foraging and Area/Row forms use this layout.

The imagery of the satellite map, user-assigned map icons, and row/area colors
continue to reflect the user's map settings.

## Verification

Automated coverage checks mode persistence/account isolation, orchard↔foraging
navigation and record separation, reopening directly in Foraging, large-text
form usability, existing orchard creation/navigation, and the full existing
regression suite. CI also builds the native apps and verifies the signed APK.

## Sharing a foraging find

Resource details offer **Share find** in both local and connected builds. It
opens the Android/iOS share sheet so the user chooses a destination. The summary
contains the resource name, classification, seasonal month range, coordinates
and a Google Maps link. Private notes, observations, photos, internal record IDs
and account/orchard identifiers are omitted. No destination is contacted without
the user's action in the device share sheet; dismissing it is not reported as a
successful delivery.

**Publish find to the community** remains a separate explicit choice. It is off
by default. Connected mode publishes the sanitized listing according to existing
Firebase rules; the phone-only build retains the preference locally and directs
users to Share find. Sharing a summary does not change a resource's publication
preference or grant access to its private orchard records.
