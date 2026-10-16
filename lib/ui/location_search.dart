import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/map_search.dart';

Future<MapLocation?> showLocationSearch(BuildContext context) =>
    showDialog<MapLocation>(context: context, builder: (_) => const _Search());

class _Search extends ConsumerStatefulWidget {
  const _Search();
  @override
  ConsumerState<_Search> createState() => _SearchState();
}

class _SearchState extends ConsumerState<_Search> {
  final query = TextEditingController();
  bool busy = false;
  String? message;
  List<MapLocation> results = [];
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (busy) return;
    final text = query.text.trim();
    if (text.isEmpty) {
      setState(() => message = 'Enter an address or latitude, longitude.');
      return;
    }
    setState(() {
      busy = true;
      message = null;
      results = [];
    });
    try {
      final coordinates = parseMapCoordinates(text);
      if (coordinates != null) {
        if (mounted) Navigator.pop(context, MapLocation(text, coordinates));
        return;
      }
      final found = await ref
          .read(addressSearchRepositoryProvider)
          .search(text);
      if (!mounted) return;
      setState(() {
        results = found;
        if (found.isEmpty) {
          message = 'No locations found. Try a fuller address or coordinates.';
        }
      });
    } on ArgumentError {
      if (mounted) {
        setState(
          () => message = 'Latitude must be −90 to 90; longitude −180 to 180.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Address lookup is unavailable. Check your connection or enter latitude, longitude.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Search map location'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: query,
              autofocus: true,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Address or latitude, longitude',
                hintText: '45.123456, -75.123456',
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => search(),
            ),
            const Text(
              'Decimal degrees, latitude first. Address lookup may require internet.',
            ),
            if (busy) const LinearProgressIndicator(),
            if (message != null) Text(message!),
            for (final result in results)
              ListTile(
                leading: const Icon(Icons.place),
                title: Text(result.label),
                subtitle: Text(
                  '${result.coordinates.latitude.toStringAsFixed(6)}, ${result.coordinates.longitude.toStringAsFixed(6)}',
                ),
                onTap: () => Navigator.pop(context, result),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : search,
        child: const Text('Search'),
      ),
    ],
  );
}
