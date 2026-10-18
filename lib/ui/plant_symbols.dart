import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../domain/models.dart';

const symbolLabels = {
  PlantSymbol.tree: '🌳',
  PlantSymbol.apple: '🍎',
  PlantSymbol.pear: '🍐',
  PlantSymbol.berry: '🫐',
  PlantSymbol.flower: '🌸',
  PlantSymbol.citrus: '🍊',
  PlantSymbol.nut: '🌰',
  PlantSymbol.vine: '🍇',
};
final markerSymbolsProvider =
    FutureProvider<Map<PlantSymbol, BitmapDescriptor>>((ref) async {
      final result = <PlantSymbol, BitmapDescriptor>{};
      for (final entry in symbolLabels.entries) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawCircle(
          const Offset(32, 32),
          30,
          Paint()..color = Colors.white,
        );
        final painter = TextPainter(
          text: TextSpan(
            text: entry.value,
            style: const TextStyle(fontSize: 40),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          Offset((64 - painter.width) / 2, (64 - painter.height) / 2),
        );
        painter.dispose();
        final picture = recorder.endRecording();
        final image = await picture.toImage(64, 64);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        result[entry.key] = BitmapDescriptor.bytes(
          bytes!.buffer.asUint8List(),
          width: 28,
          height: 28,
        );
        image.dispose();
        picture.dispose();
      }
      return result;
    });
