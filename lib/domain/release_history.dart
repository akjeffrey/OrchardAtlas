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
      'Show on Map is also available on Plant Detail.',
      'Edit open task definitions and enable local reminders without losing completed work.',
      'Capture foraging resources, seasons, observations and optional public listings.',
      'Attach camera/gallery photos with thumbnails and durable queued uploads.',
      'Explore harvest reports, copy CSV and recover edited/deleted activities.',
      'Connected orchard invitations support owner, editor and viewer access.',
    ],
  ),
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
