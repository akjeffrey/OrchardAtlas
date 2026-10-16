import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/models.dart';

/// A local coordinate sketch for credential-free trials, not a basemap.
class CoordinatePreview extends StatelessWidget {
  const CoordinatePreview({
    super.key,
    required this.plants,
    required this.selected,
    required this.focus,
    required this.onSelect,
    required this.onOpen,
  });
  final List<ManagedPlant> plants;
  final Coordinates? selected, focus;
  final ValueChanged<Coordinates> onSelect;
  final ValueChanged<String> onOpen;
  @override
  Widget build(BuildContext context) {
    final anchor =
        selected ?? focus ?? (plants.isEmpty ? null : plants.first.location);
    if (anchor == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Use Current GPS location, or Add Plant and enter coordinates.\n\nTrial coordinate preview has no satellite/map imagery.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final points = [anchor, ...plants.map((p) => p.location)];
    final minLat = math.max(
      -90.0,
      points.map((p) => p.latitude).reduce(math.min) - 0.0003,
    );
    final maxLat = math.min(
      90.0,
      points.map((p) => p.latitude).reduce(math.max) + 0.0003,
    );
    final minLon = math.max(
      -180.0,
      points.map((p) => p.longitude).reduce(math.min) - 0.0003,
    );
    final maxLon = math.min(
      180.0,
      points.map((p) => p.longitude).reduce(math.max) + 0.0003,
    );
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Coordinate preview · North ↑ · No basemap',
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) {
              final width = math.max(1.0, bounds.maxWidth - 48);
              final height = math.max(1.0, bounds.maxHeight - 48);
              Offset pixel(Coordinates p) => Offset(
                24 + (p.longitude - minLon) / (maxLon - minLon) * width,
                24 + (maxLat - p.latitude) / (maxLat - minLat) * height,
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (tap) {
                  final x = ((tap.localPosition.dx - 24) / width).clamp(
                    0.0,
                    1.0,
                  );
                  final y = ((tap.localPosition.dy - 24) / height).clamp(
                    0.0,
                    1.0,
                  );
                  onSelect(
                    Coordinates(
                      maxLat - y * (maxLat - minLat),
                      minLon + x * (maxLon - minLon),
                    ),
                  );
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                    ),
                    for (final p in plants)
                      Positioned(
                        left: pixel(p.location).dx - 24,
                        top: pixel(p.location).dy - 24,
                        child: Tooltip(
                          message: p.name,
                          child: IconButton.filledTonal(
                            tooltip: p.name,
                            onPressed: () => onOpen(p.id),
                            icon: const Icon(Icons.park),
                          ),
                        ),
                      ),
                    if (selected != null)
                      Positioned(
                        left: pixel(selected!).dx - 12,
                        top: pixel(selected!).dy - 12,
                        child: const IgnorePointer(
                          child: Icon(
                            Icons.location_on,
                            color: Colors.blue,
                            size: 24,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
