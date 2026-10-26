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
      'Tap the foraging map to drop a draggable pin; Add Resource uses that exact spot even after panning.',
      'Cancelled entry keeps the pin; successful save clears it.',
      'Share find sends a name, season and map link through your chosen app, excluding private notes and photos.',
    ],
  ),
  const ReleaseNote('0.62.0', [
    'Remembered orchard/foraging modes with a separate foraging map/list.',
    'Icon-inspired greens, ivory, red accents and consistently spaced forms.',
  ]),
  const ReleaseNote('0.58.0', [
    'Plant Detail Show on Map, task editing and local reminders.',
    'Foraging resources, camera/gallery photos and durable upload queues.',
    'Harvest reports/CSV, activity recovery and connected orchard sharing.',
  ]),
  const ReleaseNote('0.53.0', [
    'Seasonal planting uses Group, Type and Variety dropdowns.',
    'Convert annual/perennial management while preserving history.',
    'Shared list/map icons, hierarchical task targets and Edit Plant Show on Map.',
  ]),
  const ReleaseNote('0.49.0', [
    'Create custom Groups, Types and Varieties directly from Edit Plant.',
    'Rename custom icons in Settings; row endpoint dots and versioned filenames.',
  ]),
  const ReleaseNote('0.47.0', [
    'Pick Add Plant locations on the map; Add Another retains location.',
    'Anchored names, icon deletion fallback and automatic backup target after restore.',
  ]),
  const ReleaseNote('0.42.0', [
    'Edit classification names and icons in Settings.',
    'Import custom icons and include them in backups.',
    'Map icons stay bounded and shrink at wider zoom levels.',
  ]),
].take(5).toList(growable: false);
