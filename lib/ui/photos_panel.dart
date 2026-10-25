import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/extensions.dart';
import '../application/providers.dart';
import '../domain/extensions.dart';

class PhotosPanel extends ConsumerStatefulWidget {
  const PhotosPanel(this.itemId, {super.key});
  final String itemId;
  @override
  ConsumerState<PhotosPanel> createState() => _PhotosState();
}

class _PhotosState extends ConsumerState<PhotosPanel> {
  bool busy = false;
  String? error;
  Future<void> capture(bool camera) async {
    setState(() => busy = true);
    try {
      await addPhoto(ref, widget.itemId, camera: camera);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(recordsProvider(RecordKind.photo));
    final canEdit = ref.watch(canEditOrchardProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos', style: Theme.of(context).textTheme.titleLarge),
        Wrap(
          children: [
            TextButton.icon(
              onPressed: busy || !canEdit ? null : () => capture(true),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take photo'),
            ),
            TextButton.icon(
              onPressed: busy || !canEdit ? null : () => capture(false),
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose photo'),
            ),
            if (!ref.watch(trialModeProvider))
              TextButton(
                onPressed: () => ref.invalidate(photoWorkerProvider),
                child: const Text('Retry uploads'),
              ),
          ],
        ),
        if (error != null) Text(error!),
        photos.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (all) => Wrap(
            spacing: 8,
            children: [
              for (final p in all.where((p) => p['itemId'] == widget.itemId))
                SizedBox(
                  width: 120,
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FutureBuilder<Uint8List>(
                                    future: p['image'] is String
                                        ? Future.value(
                                            base64Decode(p['image'] as String),
                                          )
                                        : ref
                                              .read(photoRepositoryProvider)
                                              .read(p['storagePath'] as String),
                                    builder: (context, snapshot) =>
                                        snapshot.hasData
                                        ? Image.memory(
                                            snapshot.data!,
                                            gaplessPlayback: true,
                                          )
                                        : Column(
                                            children: [
                                              Image.memory(
                                                base64Decode(
                                                  p['thumbnail'] as String,
                                                ),
                                              ),
                                              if (snapshot.hasError)
                                                const Text(
                                                  'Full photo unavailable offline; thumbnail retained.',
                                                )
                                              else
                                                const CircularProgressIndicator(),
                                            ],
                                          ),
                                  ),
                                  Text(p['createdAt'] as String),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        child: Image.memory(
                          base64Decode(p['thumbnail'] as String),
                          width: 112,
                          height: 112,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Text(switch (p['state']) {
                        'local' => 'Saved on phone',
                        'uploaded' => 'Uploaded',
                        _ => 'Upload queued',
                      }, textAlign: TextAlign.center),
                      if (p['error'] != null) Text(p['error'] as String),
                      if (canEdit)
                        IconButton(
                          tooltip: 'Delete photo',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete photo?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (yes != true) return;
                            try {
                              final place = await ref.read(
                                placeProvider.future,
                              );
                              await ref
                                  .read(orchardRecordsProvider)
                                  .removeRecord(
                                    place.id,
                                    RecordKind.photo,
                                    p['id'] as String,
                                  );
                            } catch (e) {
                              if (mounted) setState(() => error = '$e');
                            }
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
