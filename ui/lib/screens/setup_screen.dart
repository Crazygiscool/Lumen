import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _authorCtrl = TextEditingController(text: 'Admin');
  int _step = 0;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _authorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(32),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildStep(cs),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(ColorScheme cs) {
    switch (_step) {
      case 0:
        return _buildIntro(cs);
      case 1:
        return _buildFeatures(cs);
      case 2:
        return _buildAccount(cs);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildIntro(ColorScheme cs) {
    return Column(
      key: const ValueKey(0),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.flare, color: cs.primary, size: 80),
        const SizedBox(height: 24),
        Text(
          'Welcome to Lumen',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
        ),
        const SizedBox(height: 16),
        Text(
          'A digital sanctuary for your thoughts. Private, encrypted, and offline-first.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
        ),
        const SizedBox(height: 40),
        FilledButton.icon(
          onPressed: () => setState(() => _step = 1),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Discover Features'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(200, 50),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatures(ColorScheme cs) {
    return Column(
      key: const ValueKey(1),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Why Lumen?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 24),
        _FeatureItem(
          icon: Icons.lock_outline,
          title: 'AES-256 Encryption',
          description: 'Your data is encrypted before it ever touches the disk.',
          color: cs.primary,
        ),
        _FeatureItem(
          icon: Icons.edit_note,
          title: 'Expressive Journaling',
          description: 'Capture moods, prompts, and rich text reflections.',
          color: cs.secondary,
        ),
        _FeatureItem(
          icon: Icons.task_alt,
          title: 'Deep Productivity',
          description: 'Integrated Kanban boards, Mind Maps, and Task tracking.',
          color: cs.tertiary,
        ),
        _FeatureItem(
          icon: Icons.extension_outlined,
          title: 'Modular & Extensible',
          description: 'A trait-based plugin system to build your own tools.',
          color: cs.error,
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _step = 0),
              child: const Text('Back'),
            ),
            const SizedBox(width: 16),
            FilledButton(
              onPressed: () => setState(() => _step = 2),
              child: const Text('Get Started'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAccount(ColorScheme cs) {
    return Column(
      key: const ValueKey(2),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Secure Your Vault',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        Text(
          'Set a master password. This cannot be recovered if lost.',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _authorCtrl,
          decoration: const InputDecoration(
            labelText: 'Preferred Username (Author)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Master Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmPasswordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Confirm Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: _completeSetup,
              child: const Text('Create Vault'),
            ),
          ],
        ),
      ],
    );
  }

  void _completeSetup() {
    final pw = _passwordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;

    if (pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password cannot be empty')),
      );
      return;
    }

    if (pw != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    // Set the password in the core
    final ok = ref.read(authProvider.notifier).setPassword(pw);
    if (ok) {
      // Save the master username
      ref.read(userProvider.notifier).setUsername(_authorCtrl.text.trim());
      // Setup complete! 
      // The authProvider state is now 'true', so main.dart will switch to HomeScreen.
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to set password')),
      );
    }
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
