import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _passwordCtrl = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flare, color: cs.primary, size: 64),
              const SizedBox(height: 16),
              Text(
                'Lumen',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your password to unlock',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  errorText: _error ? 'Incorrect password' : null,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _unlock(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _unlock,
                child: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _unlock() {
    // For now, use a fixed salt. In production, this would be stored per vault.
    const salt = 'lumen_session_salt';
    final ok = ref.read(authProvider.notifier).unlock(
          _passwordCtrl.text,
          salt,
        );
    if (!ok) {
      setState(() => _error = true);
    }
  }
}
