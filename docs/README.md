# OrchardAtlas design baseline

Written before application implementation for the V1 foundation. These documents
are the reviewable contract for the first vertical slice; future scope is explicitly
separated from shipped behavior.

1. [Product requirements](product-requirements.md)
2. [System architecture](architecture.md)
3. [Domain and data model](domain-model.md)
4. [Firestore schema](firestore-schema.md)
5. [UI and UX](ui-ux.md)
6. [Security and sharing](security-sharing.md)
7. [Offline-first behavior](offline-first.md)
8. [V1 implementation plan](v1-plan.md)
9. [Developer setup](developer-setup.md)
10. [Ongoing feature backlog](FEATURE_BACKLOG.md)

See [validation and release checks](validation.md) for observed results and remaining native testing.

[Android phone trial and installation](phone-trial.md) describes local trial storage, Maps setup and the downloadable APK.

## Product specification and trial expansion

- [Supplied OrchardAtlas specification](ORCHARDATLAS_CODEX_SPEC.md)
- [ADR-002: plant management and tasks](adr/002-trial-management.md), including scope, date inheritance, persistence, security and acceptance checks for the next trial increment.

- [ADR-003: group tasks, orchard layout and seasons](adr/003-groups-layout-seasons.md) describes the Trial 0.3 implementation contract and acceptance scenarios.

- [ADR-005: multiple orchards and saved map views](adr/005-orchards-and-map-defaults.md) describes orchard selection, isolation and default-camera persistence.
