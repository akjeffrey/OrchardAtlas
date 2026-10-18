import 'dart:typed_data';

import 'models.dart';

/// Small, self-contained PNG assets. No device file path or cloud SDK leaks here.
class MapIcon {
  MapIcon({required this.id, required String name, required Uint8List png})
    : name = requiredText(name, 'Icon name'),
      png = validatedCopy(png);

  static Uint8List validatedCopy(Uint8List bytes) {
    validatePng(bytes);
    return Uint8List.fromList(bytes).asUnmodifiableView();
  }

  static const maxBytes = 32768;
  static const maxDimension = 96;
  static const maxPerOrchard = 128;
  final String id, name;
  final Uint8List png;

  static void validatePng(Uint8List bytes) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 33 ||
        bytes.length > maxBytes ||
        !List.generate(8, (i) => bytes[i] == signature[i]).every((v) => v) ||
        String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
      throw const FormatException('Use a normalized PNG icon up to 32 KB');
    }
    final data = ByteData.sublistView(bytes);
    final width = data.getUint32(16), height = data.getUint32(20);
    if (width < 1 ||
        height < 1 ||
        width > maxDimension ||
        height > maxDimension) {
      throw const FormatException('Icon dimensions must be at most 96 × 96');
    }
    var offset = 8, chunks = 0;
    var hasData = false, ended = false;
    while (offset + 12 <= bytes.length) {
      final length = data.getUint32(offset);
      if (offset + 12 + length > bytes.length) {
        throw const FormatException('Truncated icon PNG');
      }
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      if (chunks++ == 0 && (type != 'IHDR' || length != 13)) {
        throw const FormatException('Invalid PNG header');
      }
      var crc = 0xffffffff;
      for (var i = offset + 4; i < offset + 8 + length; i++) {
        crc ^= bytes[i];
        for (var bit = 0; bit < 8; bit++) {
          crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
        }
      }
      if ((crc ^ 0xffffffff) != data.getUint32(offset + 8 + length)) {
        throw const FormatException('Corrupt icon PNG');
      }
      if (type == 'IDAT') hasData = true;
      offset += length + 12;
      if (type == 'IEND') {
        ended = length == 0;
        break;
      }
    }
    if (!hasData || !ended || offset != bytes.length) {
      throw const FormatException('Incomplete icon PNG');
    }
  }
}

abstract interface class IconImporter {
  /// User-selected image, normalized to a bounded PNG; null means cancelled.
  Future<Uint8List?> importPng();
}

/// Logical screen pixels, never a geographic size. Discrete tiers avoid rerenders
/// for each camera frame and shrink markers as more of the orchard is visible.
double markerSizeForZoom(double zoom) => zoom < 13
    ? 16
    : zoom < 16
    ? 22
    : 28;
