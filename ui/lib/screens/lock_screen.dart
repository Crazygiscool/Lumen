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
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _unlock() async {
    if (_passwordCtrl.text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = false;
    });

    // Deriving Argon2 key is slow, so we use a small delay to ensure the UI updates
    await Future.delayed(const Duration(milliseconds: 10));
    
    final ok = ref.read(authProvider.notifier).unlock(_passwordCtrl.text);
    if (!ok) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
        _passwordCtrl.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.surface,
                  cs.surfaceContainerLow,
                ],
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.flare, color: cs.primary, size: 64),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Lumen',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Illumination for your thoughts.',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
                      ),
                      const SizedBox(height: 48),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        autofocus: true,
                        enabled: !_loading,
                        decoration: InputDecoration(
                          labelText: 'Master Password',
                          hintText: 'Enter to unlock vault',
                          errorText: _error ? 'Incorrect password. Try again.' : null,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                          filled: true,
                          fillColor: cs.surface,
                        ),
                        onSubmitted: (_) => _unlock(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed: _loading ? null : _unlock,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                                )
                              : const Text('Unlock Vault', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _loading ? null : () {
                          // Maybe a "forgot password" warning?
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Lost Password?'),
                              content: const Text('Lumen uses end-to-end encryption. If you lose your master password, your data cannot be recovered.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('I Understand')),
                              ],
                            ),
                          );
                        },
                        child: Text('Forgot Password?', style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
