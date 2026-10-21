import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../data/backup_documents.dart';

final appVersionProvider = FutureProvider<String>(
  (ref) => AndroidBackupDocuments.appVersion(),
);

/// One version label for all routes, including pushed editors and Settings.
class AppVersionBanner extends ConsumerWidget {
  const AppVersionBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    bottom: false,
    child: Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            'OrchardAtlas ${ref.watch(appVersionProvider).valueOrNull ?? '…'}'
            '${ref.watch(trialModeProvider) ? ' · Saved on this phone' : ''}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ),
    ),
  );
}
