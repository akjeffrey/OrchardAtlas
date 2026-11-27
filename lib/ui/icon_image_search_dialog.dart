import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../domain/map_icons.dart';

class IconImageSearchDialog extends ConsumerStatefulWidget {
  const IconImageSearchDialog({super.key});
  @override
  ConsumerState<IconImageSearchDialog> createState() => _IconImageSearchState();
}

class _IconImageSearchState extends ConsumerState<IconImageSearchDialog> {
  final query = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (busy) {
      return;
    }
    try {
      googleIconImageSearchUri(query.text);
      setState(() {
        busy = true;
        error = null;
      });
      await ref.read(iconImageSearchProvider).search(query.text);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => error = e.message ?? 'Could not open your browser.');
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => error = 'Image search is unavailable on this device.');
      }
    } on ArgumentError {
      if (mounted) {
        setState(() => error = 'Enter a search of 1–200 characters.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not open Google Images. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Search Google Images'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Search in your browser, save an image to Downloads or Files, then return here and tap Import image.',
          ),
          TextField(
            controller: query,
            autofocus: true,
            maxLength: 200,
            enabled: !busy,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => search(),
            decoration: InputDecoration(
              labelText: 'Search for an icon',
              hintText: 'e.g. pear tree icon transparent',
              errorText: error,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: busy ? null : search,
        icon: const Icon(Icons.open_in_browser),
        label: Text(busy ? 'Opening…' : 'Search images'),
      ),
    ],
  );
}
