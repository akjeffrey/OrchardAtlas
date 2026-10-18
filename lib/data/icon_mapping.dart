import 'dart:convert';

import '../domain/map_icons.dart';

class IconMapping {
  static Map<String, dynamic> write(MapIcon icon) => {
    'schemaVersion': 1,
    'name': icon.name,
    'png': base64Encode(icon.png),
  };
  static MapIcon read(String id, Map<String, dynamic> data) {
    final raw = data['png'];
    if (data['schemaVersion'] != 1 || raw is! String || raw.length > 43692) {
      throw const FormatException('Invalid icon record');
    }
    return MapIcon(
      id: id,
      name: data['name'] as String,
      png: base64Decode(raw),
    );
  }
}
