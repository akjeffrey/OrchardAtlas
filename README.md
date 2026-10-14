# OrchardAtlas

Flutter mobile app for mapping orchard plants and recording care and harvests,
with native Firestore offline persistence. V1 provides map/list → GPS or manual
position → hierarchical taxonomy → plant detail → activities and annual harvest
totals, plus **Add Another Like This** for orchard rows.

Start with the [design documentation](docs/README.md) and
[developer setup](docs/developer-setup.md). Firebase/Maps configuration is supplied
locally and is not included. Sharing, tasks, foraging-resource UI and photo uploads
are future slices; their domain boundaries are documented.

```sh
flutter pub get
flutter analyze
flutter test
```

See [validation and remaining device checks](docs/validation.md) for the limits of
automated testing. This foundation is not a configured production deployment.
