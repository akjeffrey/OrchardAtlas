# V1 implementation plan

## Sequence
1. Commit this design baseline before any application code.
2. Scaffold Flutter Android/iOS project; pin resolved dependencies and configure
   analysis/CI. Keep generated Firebase/Maps configuration out of Git.
3. Add pure Dart entities, taxonomy fixture, validation, aggregation and ports.
4. Add strict Firestore DTO mapping, repository snapshot/write-error streams,
   Firebase auth, foreground GPS and Storage boundary; add rules and rule tests.
5. Compose Riverpod providers and go_router auth routes. Implement map/list,
   GPS/manual location, dependent taxonomy form, detail/history/year totals,
   activity/harvest form and add-another template.
6. Exercise unit/mapper tests, static analysis and emulator authorization tests.
7. Document exact setup and physical-device offline checks. Commit implementation
   and open a PR against main; do not merge.

## Automated checks
Domain: invalid coordinates/quantity/dates, unit conversion, annual boundaries,
count separation, taxonomy ancestry, template identity/location reset.
Mapping: native types, round trips, unknown versions/types and malformed data.
Repositories: cached snapshots, queued writes and delayed rejection using injected
Firestore fakes where practical. Rules: owner, stranger, malformed payload,
forged author, immutable events, reserved-path access. UI: injected repositories
for form behavior, totals and add-another; map plugin needs device smoke checks.

## Release gates
Configure real Firebase and Google Maps projects and native platform prerequisites.
Deploy tested security rules. Run Android/iOS builds with ignored local config.
Perform the complete GPS/offline restart scenario on physical devices. CI unit
checks do not establish native Maps/GPS/Firebase readiness. Sharing, photo uploads,
and tasks remain explicitly deferred. All known limitations go into PR validation.
