import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/providers.dart';
import '../domain/models.dart';
import 'common.dart';

class ArchivedPlantsScreen extends ConsumerWidget {
  const ArchivedPlantsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Archived Plants')),
    body: ref
        .watch(plantsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorPanel(e),
          data: (s) {
            final plants = s.value
                .where((p) => p.status == ItemStatus.archived)
                .toList();
            return plants.isEmpty
                ? const Center(child: Text('No archived plants.'))
                : ListView(
                    children: [
                      for (final p in plants)
                        ListTile(
                          title: Text(p.name),
                          onTap: () => context.push('/plants/${p.id}'),
                          subtitle: const Text('Tap to view history or edit'),
                          trailing: IconButton(
                            tooltip: 'Unarchive plant',
                            icon: const Icon(Icons.unarchive),
                            onPressed: () => ref
                                .read(orchardRepositoryProvider)
                                .updatePlant(
                                  p.copyWith(status: ItemStatus.active),
                                ),
                          ),
                        ),
                    ],
                  );
          },
        ),
  );
}
