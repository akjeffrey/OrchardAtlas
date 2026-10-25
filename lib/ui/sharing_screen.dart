import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../application/extensions.dart';
import '../domain/models.dart';
import 'common.dart';

class SharingScreen extends ConsumerStatefulWidget {
  const SharingScreen({super.key});
  @override
  ConsumerState<SharingScreen> createState() => _SharingState();
}

class _SharingState extends ConsumerState<SharingScreen> {
  final email = TextEditingController();
  PermissionRole role = PermissionRole.viewer;
  String? message;
  bool busy = false;
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> act(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) setState(() => message = 'Saved');
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(sharingProvider),
        place = ref.watch(placeProvider).valueOrNull;
    final uid = ref.watch(userProvider).valueOrNull?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Orchard sharing')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (repo == null)
            const Text(
              'Sharing requires a connected Firebase account. This installation keeps its data on the phone and in your chosen Drive backup. File access is managed in Google Drive; app roles apply to connected orchards.',
            ),
          if (repo != null && place != null) ...[
            Text(place.name, style: Theme.of(context).textTheme.headlineSmall),
            Text('Owner: ${place.ownerId}'),
            if (place.ownerId == uid) ...[
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Invite by verified account email',
                ),
              ),
              DropdownButtonFormField<PermissionRole>(
                initialValue: role,
                items: [
                  for (final r in [
                    PermissionRole.viewer,
                    PermissionRole.editor,
                  ])
                    DropdownMenuItem(value: r, child: Text(r.name)),
                ],
                onChanged: (r) => setState(() => role = r!),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => act(() => repo.invite(place, email.text, role)),
                child: const Text('Send invitation'),
              ),
              const Text(
                'Editors can change orchard records. Viewers can read records. Only the owner manages access. Ask invitees to verify their email before accepting.',
              ),
            ],
            ref
                .watch(orchardMembersProvider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => ErrorPanel(e),
                  data: (members) => Column(
                    children: [
                      for (final m in members)
                        ListTile(
                          title: Text(m.userId),
                          subtitle: Text(m.role.name),
                          trailing: place.ownerId == uid
                              ? IconButton(
                                  tooltip: 'Revoke access',
                                  icon: const Icon(Icons.person_remove),
                                  onPressed: busy
                                      ? null
                                      : () => act(
                                          () => repo.revoke(place.id, m.userId),
                                        ),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
            const Divider(),
            Text(
              'Invitations for you',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ref
                .watch(incomingInvitationsProvider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => ErrorPanel(e),
                  data: (invitations) => Column(
                    children: [
                      for (final i in invitations)
                        ListTile(
                          title: Text(i.orchardName),
                          subtitle: Text('${i.role.name} · ${i.email}'),
                          trailing: TextButton(
                            onPressed: busy
                                ? null
                                : () => act(() async {
                                    final accepted = await repo.accept(i, uid!);
                                    await ref
                                        .read(orchardDirectoryProvider)
                                        .selectPlace(uid, accepted.id);
                                    ref
                                            .read(
                                              selectedOrchardProvider.notifier,
                                            )
                                            .state =
                                        accepted;
                                  }),
                            child: const Text('Accept'),
                          ),
                        ),
                      if (invitations.isEmpty)
                        const Text('No pending invitations.'),
                    ],
                  ),
                ),
          ],
          if (message != null) Text(message!),
        ],
      ),
    );
  }
}
