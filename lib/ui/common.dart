import 'package:flutter/material.dart';

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

class SyncStatus extends StatelessWidget {
  const SyncStatus(this.snapshot, {super.key});
  final RepositorySnapshot<dynamic> snapshot;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(
      snapshot.hasPendingWrites
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
  _ => '${type[0].toUpperCase()}${type.substring(1)}',
};
