# Requested backlog release

Implements the additions requested after Trial 0.5: row direction/order, inherited
section location, grouped/archived marker suppression, section styling and basemap,
orchard naming, Group/Type/Variety selectors, Android immersive display, matching
section visibility, archive list, complete plant edits and permanent cascade deletion,
task sorting/filtering, dynamic matching targets, repeat occurrences, linked task
activities, activity editing/deletion and classification overviews. One Area polygon
type replaces Bed; Row remains a line. Existing IDs and data stay intact.

Original deferred work remains excluded: sharing, foraging, photo capture/upload,
background reminders, general exports/backups, production distribution and unrelated
advanced mapping/reporting. Existing photo records/files are included in deletion.

Legacy genus/species/cultivar identifiers remain readable. The three selectors show
Group, Type (legacy genus) and Variety (legacy species/cultivar); existing cultivars
remain selectable in the Variety list. New entries use three levels. Legacy Bed
records read as Area and save as Area without changing identity or membership.

Rows retain ordered geometry: first vertex is start, last is finish, intermediate
vertices describe the route. Plants default to section location. A persisted row
order overrides spatial projection; rearrangement does not change GPS coordinates.

Task plans store targeting criteria and optional recurrence/activity choices. Each
occurrence/target has a stable UUID and independent completion. Current and missed
occurrences are retained, with calendar-aware monthly/yearly intervals. Zero-target
plans are valid. New active matches join automatically; earlier completions remain.
Task completion and its generated plant event are written together. Reopening removes
only that task's linked event. Editing/deleting activities is explicitly authorized
by this release and supersedes the previous append-only UI/rules restriction.

Permanent deletion previews affected records and requires an in-app confirmation.
Local trial cascades persist as one snapshot per orchard. Complete Firestore
cascades require network so uncached children are discovered; record writes and task
completion continue to use offline persistence. Firestore and Storage ownership
rules must protect mutations and cross-orchard references. No credentials enter Git.

Verification covers migrations, row ordering, dynamic membership/zero matches,
calendar recurrence, independent completion, idempotent event links/reopening,
deletion scope, mutable fields, sorting preferences, selector compatibility and UI
entry points. CI must pass before the authorized merge and phone artifact publication.
