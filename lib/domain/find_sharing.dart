import 'extensions.dart';

abstract interface class FindSharingRepository {
  /// Opens the device share sheet. A return does not prove a recipient received it.
  Future<void> share(String text);
}

/// A deliberately bounded public summary: no private notes, photos or account IDs.
String findShareText(ResourceRecord find, {String? classification}) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final latitude = find.location.latitude.toStringAsFixed(7);
  final longitude = find.location.longitude.toStringAsFixed(7);
  final query = Uri.encodeComponent('$latitude,$longitude');
  return [
    'Foraging find: ${find.name}',
    if (classification != null && classification.trim().isNotEmpty)
      'Classification: $classification',
    'Season: ${months[find.startMonth - 1]}–${months[find.endMonth - 1]}',
    'Location: $latitude, $longitude',
    'https://www.google.com/maps/search/?api=1&query=$query',
    'Shared with OrchardAtlas',
  ].join('\n');
}
