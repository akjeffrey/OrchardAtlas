import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Zoom/pan stay in this view; the transformed grid keeps its selection state.
class SeedTrayViewport extends StatefulWidget {
  const SeedTrayViewport({
    super.key,
    required this.contentSize,
    required this.child,
  });
  final Size contentSize;
  final Widget child;
  @override
  State<SeedTrayViewport> createState() => _SeedTrayViewportState();
}

class _SeedTrayViewportState extends State<SeedTrayViewport> {
  final transform = TransformationController();
  Size viewportSize = Size.zero;
  static const minZoom = 0.01, maxZoom = 3.0;
  double get zoom => transform.value.getMaxScaleOnAxis();
  @override
  void initState() {
    super.initState();
    transform.addListener(changed);
  }

  void changed() {
    setState(() {});
  }

  @override
  void dispose() {
    transform.removeListener(changed);
    transform.dispose();
    super.dispose();
  }

  void zoomTo(double value) {
    final size = viewportSize;
    if (size.isEmpty) {
      return;
    }
    final next = value.clamp(minZoom, maxZoom).toDouble();
    final center = Offset(size.width / 2, size.height / 2);
    final point = transform.toScene(center);
    transform.value = Matrix4.diagonal3Values(next, next, next)
      ..setTranslationRaw(
        center.dx - point.dx * next,
        center.dy - point.dy * next,
        0,
      );
  }

  void fit() {
    final size = viewportSize;
    if (size.isEmpty) {
      return;
    }
    final scale = math
        .min(
          size.width / widget.contentSize.width,
          size.height / widget.contentSize.height,
        )
        .clamp(minZoom, 1.0)
        .toDouble();
    transform.value = Matrix4.diagonal3Values(scale, scale, scale)
      ..setTranslationRaw(
        (size.width - widget.contentSize.width * scale) / 2,
        (size.height - widget.contentSize.height * scale) / 2,
        0,
      );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: 'Zoom out tray',
            icon: const Icon(Icons.zoom_out),
            onPressed: zoom <= minZoom + 0.001
                ? null
                : () => zoomTo(zoom / 1.25),
          ),
          Text(
            '${(zoom * 100).round()}%',
            key: const ValueKey('tray-zoom-level'),
          ),
          IconButton(
            tooltip: 'Zoom in tray',
            icon: const Icon(Icons.zoom_in),
            onPressed: zoom >= maxZoom - 0.001
                ? null
                : () => zoomTo(zoom * 1.25),
          ),
          TextButton(onPressed: fit, child: const Text('Fit tray')),
          IconButton(
            tooltip: 'Reset tray zoom',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => transform.value = Matrix4.identity(),
          ),
        ],
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            viewportSize = constraints.biggest;
            return SizedBox.expand(
              child: InteractiveViewer(
                key: const ValueKey('tray-interactive-viewer'),
                transformationController: transform,
                constrained: false,
                alignment: Alignment.topLeft,
                minScale: minZoom,
                maxScale: maxZoom,
                boundaryMargin: const EdgeInsets.all(200),
                trackpadScrollCausesScale: true,
                child: SizedBox(
                  width: widget.contentSize.width,
                  height: widget.contentSize.height,
                  child: widget.child,
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}
