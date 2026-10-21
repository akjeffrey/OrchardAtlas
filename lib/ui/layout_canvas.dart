import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import 'icon_picker.dart';

import '../domain/models.dart';
import '../domain/landscape.dart';
import '../domain/work.dart';

class LayoutCanvas extends ConsumerWidget {
  const LayoutCanvas({
    super.key,
    this.sections = const [],
    this.plants = const [],
    this.draft = const [],
    this.selected,
    this.center,
    this.span,
    this.onTap,
    this.onSection,
    this.onPlant,
    this.iconSize = 28,
    this.endpointSize = 10,
    this.selectedPlantId,
    this.selectedSectionId,
  });
  final double iconSize, endpointSize;
  final String? selectedPlantId, selectedSectionId;
  final List<OrchardSection> sections;
  final List<ManagedPlant> plants;
  final List<Coordinates> draft;
  final Coordinates? selected, center;
  final double? span;
  final ValueChanged<Coordinates>? onTap;
  final ValueChanged<String>? onSection, onPlant;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taxonomy = ref.watch(taxonomyProvider);
    Taxon? appearance(String id) =>
        taxonomy.taxa.any((t) => t.id == id) ? taxonomy.iconFor(id) : null;
    final points = [
      ...sections.expand((s) => s.vertices),
      ...plants.map((p) => p.location),
      ...draft,
      ?selected,
      ?center,
    ];
    if (points.isEmpty) {
      return const Center(
        child: Text(
          'Capture GPS or enter a coordinate to start.\nGoogle Maps is not configured.',
          textAlign: TextAlign.center,
        ),
      );
    }
    final minLat = center != null && span != null
        ? math.max(-90.0, center!.latitude - span!)
        : math.max(
            -90.0,
            points.map((p) => p.latitude).reduce(math.min) - 0.0002,
          );
    final maxLat = center != null && span != null
        ? math.min(90.0, center!.latitude + span!)
        : math.min(
            90.0,
            points.map((p) => p.latitude).reduce(math.max) + 0.0002,
          );
    final minLon = center != null && span != null
        ? math.max(-180.0, center!.longitude - span!)
        : math.max(
            -180.0,
            points.map((p) => p.longitude).reduce(math.min) - 0.0002,
          );
    final maxLon = center != null && span != null
        ? math.min(180.0, center!.longitude + span!)
        : math.min(
            180.0,
            points.map((p) => p.longitude).reduce(math.max) + 0.0002,
          );
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = math.max(1.0, bounds.maxWidth - 48),
            height = math.max(1.0, bounds.maxHeight - 48);
        Offset pixel(Coordinates p) => Offset(
          24 + (p.longitude - minLon) / (maxLon - minLon) * width,
          24 + (maxLat - p.latitude) / (maxLat - minLat) * height,
        );
        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onTap == null
                ? null
                : (tap) => onTap!(
                    Coordinates(
                      maxLat -
                          ((tap.localPosition.dy - 24) / height).clamp(
                                0.0,
                                1.0,
                              ) *
                              (maxLat - minLat),
                      minLon +
                          ((tap.localPosition.dx - 24) / width).clamp(
                                0.0,
                                1.0,
                              ) *
                              (maxLon - minLon),
                    ),
                  ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                ),
                CustomPaint(
                  painter: _Shapes(
                    sections: sections,
                    draft: draft,
                    pixel: pixel,
                  ),
                ),
                const Positioned(
                  left: 8,
                  top: 4,
                  child: Text('Coordinate sketch · North ↑ · No basemap'),
                ),
                for (final s in sections)
                  Positioned(
                    left: pixel(sectionCenter(s)).dx - 24,
                    top: pixel(sectionCenter(s)).dy - 24,
                    child: IconButton(
                      tooltip: s.name,
                      onPressed: onSection == null
                          ? null
                          : () => onSection!(s.id),
                      icon: Icon(
                        s.kind == SectionKind.row
                            ? Icons.timeline
                            : Icons.crop_square,
                        size: iconSize,
                      ),
                    ),
                  ),
                for (final p in plants)
                  Positioned(
                    left: pixel(p.location).dx - 20,
                    top: pixel(p.location).dy - 20,
                    child: IconButton(
                      tooltip: p.name,
                      onPressed: onPlant == null ? null : () => onPlant!(p.id),
                      icon: IconPreview(
                        symbol: appearance(p.taxonId)?.symbol,
                        customIconId: appearance(p.taxonId)?.customIconId,
                        size: iconSize,
                      ),
                    ),
                  ),
                for (final s in sections)
                  if (s.symbol != null || s.customIconId != null)
                    Positioned(
                      left: pixel(sectionCenter(s)).dx - 24,
                      top: pixel(sectionCenter(s)).dy - 24,
                      child: IconButton(
                        tooltip: s.name,
                        onPressed: onSection == null
                            ? null
                            : () => onSection!(s.id),
                        icon: IconPreview(
                          symbol: s.symbol,
                          customIconId: s.customIconId,
                          size: iconSize,
                        ),
                      ),
                    ),
                for (final feature in [
                  for (final p in plants.where((p) => p.id == selectedPlantId))
                    (p.name, p.location),
                  for (final s in sections.where(
                    (s) => s.id == selectedSectionId,
                  ))
                    (s.name, sectionCenter(s)),
                ])
                  Positioned(
                    left: pixel(feature.$2).dx,
                    top: pixel(feature.$2).dy - 24,
                    child: FractionalTranslation(
                      translation: const Offset(-.5, -1),
                      child: IgnorePointer(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 200),
                              child: Text(
                                feature.$1,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                for (final row in sections.where(
                  (s) => s.kind == SectionKind.row,
                ))
                  for (final start in [true, false])
                    Positioned(
                      left:
                          pixel(start ? row.vertices.first : row.vertices.last)
                              .dx -
                          24,
                      top:
                          pixel(start ? row.vertices.first : row.vertices.last)
                              .dy -
                          24,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          tooltip:
                              '${row.name} · ${start ? 'Start (1)' : 'Finish'}',
                          onPressed: onSection == null
                              ? null
                              : () => onSection!(row.id),
                          icon: Container(
                            width: endpointSize,
                            height: endpointSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: start
                                  ? Colors.green.shade800
                                  : Colors.red.shade800,
                              border: Border.all(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                if (selected != null)
                  Positioned(
                    left: pixel(selected!).dx - 12,
                    top: pixel(selected!).dy - 24,
                    child: const IgnorePointer(
                      child: Icon(Icons.location_on, color: Colors.blue),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Shapes extends CustomPainter {
  _Shapes({required this.sections, required this.draft, required this.pixel});
  final List<OrchardSection> sections;
  final List<Coordinates> draft;
  final Offset Function(Coordinates) pixel;
  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sections) {
      final path = Path()
        ..moveTo(pixel(s.vertices.first).dx, pixel(s.vertices.first).dy);
      for (final p in s.vertices.skip(1)) {
        path.lineTo(pixel(p).dx, pixel(p).dy);
      }
      if (s.kind != SectionKind.row) {
        path.close();
        canvas.drawPath(
          path,
          Paint()..color = Colors.green.withValues(alpha: 0.12),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = (s.kind == SectionKind.row ? Colors.blue : Colors.green)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    if (draft.isNotEmpty) {
      final path = Path()..moveTo(pixel(draft.first).dx, pixel(draft.first).dy);
      for (final p in draft.skip(1)) {
        path.lineTo(pixel(p).dx, pixel(p).dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.deepOrange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      for (var i = 0; i < draft.length; i++) {
        canvas.drawCircle(
          pixel(draft[i]),
          5,
          Paint()..color = Colors.deepOrange,
        );
        final text = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: const TextStyle(color: Colors.black, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, pixel(draft[i]) + const Offset(6, 2));
        text.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Shapes oldDelegate) => true;
}
