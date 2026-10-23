import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/release_history.dart';
import 'app_version_banner.dart';

class VersionHistoryScreen extends ConsumerWidget {
  const VersionHistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Version History')),
    body: ref
        .watch(appVersionProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('Version information is unavailable.')),
          data: (version) => ListView(
            children: [
              for (final release in recentReleases(version))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Version ${release.version}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        for (final change in release.changes)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('• $change'),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
  );
}
