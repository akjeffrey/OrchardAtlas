import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import 'orchard_theme.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInState();
}

class _SignInState extends ConsumerState<SignInScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit(bool register) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      if (register) {
        await auth.register(email.text, password.text);
      } else {
        await auth.signIn(email.text, password.text);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to authenticate. Check your credentials and Internet connection.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('OrchardAtlas')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Image.asset(OrchardBrand.logo, width: 88, height: 88),
            ),
            const SizedBox(height: 20),
            Text(
              'Your orchard, season by season',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'First sign-in needs Internet. Returning sessions can work with cached records offline.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              autofillHints: const [AutofillHints.password],
            ),
            if (error != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : () => submit(false),
              child: Text(busy ? 'Please wait…' : 'Sign in'),
            ),
            TextButton(
              onPressed: busy ? null : () => submit(true),
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
    ),
  );
}
