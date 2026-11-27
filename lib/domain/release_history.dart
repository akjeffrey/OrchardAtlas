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
      'Edit repeating task start dates while preserving current completion history.',
      'Change Group / Type / Variety targets and include or exclude individual plants.',
      'Delete entire tasks, stop future repeats and retain completed plant activities.',
    ],
  ),
  const ReleaseNote('0.97.0', [
    'Search Google Images from Custom icons and import saved images.',
  ]),
  const ReleaseNote('0.93.0', [
    'Seed tray pinch, pan, zoom buttons and Fit tray controls.',
    'Use the seed-packet front photo as a planted cell icon, including offline.',
  ]),
  const ReleaseNote('0.87.0', [
    'Complete/reopen checkboxes, skip arrows and confirmed task-entry deletion.',
    'One edit control beside the group task heading.',
  ]),
  const ReleaseNote('0.83.0', [
    'Task start dates, optional end dates and recurring date ranges.',
    'Multiple local reminders and optional Google Calendar sync.',
  ]),
  const ReleaseNote('0.77.0', [
    'Seed cell planting dates, expected transplant dates and actual transplant tracking.',
    'Front/back seed-packet photos and tray deletion with offline backups.',
  ]),
  const ReleaseNote('0.70.0', [
    'Seed Starter trays, custom row/column counts and bulk cell selection.',
    'Seed/plant classifications and icons with offline persistence and Drive backups.',
  ]),
  const ReleaseNote('0.65.0', [
    'Tap and drag a foraging pin; Add Resource keeps the selected location.',
    'Share find through the device share sheet without private notes or photos.',
  ]),
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
