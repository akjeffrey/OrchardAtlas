class ReleaseNote {
  const ReleaseNote(this.version, this.changes);
  final String version;
  final List<String> changes;
}

/// Four previous feature updates plus the installed build's current update.
/// When shipping the next feature update, move these current notes into history.
List<ReleaseNote> recentReleases(String installedVersion) => [
  ReleaseNote(
    RegExp(r'\d+\.\d+\.\d+').firstMatch(installedVersion)?.group(0) ??
        installedVersion,
    const [
      'Seasonal planting uses Group, Type and Variety dropdowns.',
      'Convert existing plants between annual and perennial management without losing their history.',
      'Plant lists use the same icons as the map and include seasonal plantings.',
      'Choose task targets by Group, optional Type and optional Variety.',
      'Show on Map from Edit Plant centers the saved plant with its name selected, while keeping the edit draft.',
      'Version History shows the five most recent feature updates.',
    ],
  ),
  const ReleaseNote('0.49.0', [
    'Create custom Groups, Types and Varieties directly from Edit Plant.',
    'Rename custom icons in Settings.',
    'Small green/red dots replace row endpoint flags.',
    'Versioned ZIP/APK names and screen labels replace trial branding.',
  ]),
  const ReleaseNote('0.47.0', [
    'Choose Add Plant locations on the map; Add Another keeps the previous location.',
    'Names stay anchored beside plants, Areas and Rows.',
    'Delete custom icons with a question-mark fallback.',
    'Restore offers to use the restored file for automatic backups, defaulting to Yes.',
  ]),
  const ReleaseNote('0.42.0', [
    'Edit classification names and icons in Settings.',
    'Import custom icons and include them in backups.',
    'Map icons stay bounded and shrink at wider zoom levels.',
  ]),
  const ReleaseNote('0.39.0', [
    'Permanent APK signing and verification enable compatible in-place updates.',
    'Published APK identity is checked against its version, package and signing certificate.',
  ]),
].take(5).toList(growable: false);
