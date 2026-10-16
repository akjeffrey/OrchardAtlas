import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';

import '../domain/repositories.dart';

class ErrorPanel extends StatelessWidget {
  const ErrorPanel(this.error, {super.key, this.retry});
  final Object error;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$error', textAlign: TextAlign.center),
          if (retry != null)
            FilledButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class SyncStatus extends ConsumerWidget {
  const SyncStatus(this.snapshot, {super.key});
  final RepositorySnapshot<dynamic> snapshot;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(
      ref.watch(trialModeProvider)
          ? (snapshot.hasPendingWrites
                ? 'Saving on this phone…'
                : 'Saved on this phone · Trial data')
          : snapshot.hasPendingWrites
          ? 'Saved locally · Pending sync'
          : snapshot.isFromCache
          ? 'Cached data · May be incomplete'
          : 'Up to date',
      semanticsLabel: snapshot.hasPendingWrites
          ? 'Records pending synchronization'
          : null,
    ),
  );
}

String activityLabel(String type) => switch (type) {
  'pestsDisease' => 'Pests / disease',
  'budBreak' => 'Bud break',
  'firstBloom' => 'First bloom',
  'fullBloom' => 'Full bloom',
  'petalFall' => 'Petal fall',
  'fruitSet' => 'Fruit set',
  'harvestStart' => 'Harvest start',
  'harvestEnd' => 'Harvest end',
  _ => '${type[0].toUpperCase()}${type.substring(1)}',
};
