import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(32),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildStep(cs, l10n),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(ColorScheme cs, AppLocalizations l10n) {
    switch (_step) {
      case 0:
        return _buildIntro(cs, l10n);
      case 1:
        return _buildFeatures(cs, l10n);
      case 2:
        return _buildAccount(cs, l10n);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildIntro(ColorScheme cs, AppLocalizations l10n) {
    return Column(
      key: const ValueKey(0),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.flare, color: cs.primary, size: 80),
        const SizedBox(height: 24),
        Text(
          l10n.welcomeToLumen,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.lumenDescription,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
        ),
        const SizedBox(height: 40),
        FilledButton.icon(
          onPressed: () => setState(() => _step = 1),
          icon: const Icon(Icons.arrow_forward),
          label: Text(l10n.discoverFeatures),
          style: FilledButton.styleFrom(
            minimumSize: const Size(200, 50),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatures(ColorScheme cs, AppLocalizations l10n) {
    return Column(
      key: const ValueKey(1),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.whyLumen,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 24),
        _FeatureItem(
          icon: Icons.lock_outline,
          title: l10n.aesEncryption,
          description: l10n.encryptionDesc,
          color: cs.primary,
        ),
        _FeatureItem(
          icon: Icons.edit_note,
          title: l10n.expressiveJournaling,
          description: l10n.journalingDesc,
          color: cs.secondary,
        ),
        _FeatureItem(
          icon: Icons.task_alt,
          title: l10n.deepProductivity,
          description: l10n.productivityDesc,
          color: cs.tertiary,
        ),
        _FeatureItem(
          icon: Icons.extension_outlined,
          title: l10n.modularExtensible,
          description: l10n.modularDesc,
          color: cs.error,
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _step = 0),
              child: Text(l10n.back),
            ),
            const SizedBox(width: 16),
            FilledButton(
              onPressed: () => setState(() => _step = 2),
              child: Text(l10n.getStarted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAccount(ColorScheme cs, AppLocalizations l10n) {
    return Column(
      key: const ValueKey(2),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.secureYourVault,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.setPasswordDesc,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _authorCtrl,
          decoration: InputDecoration(
            labelText: l10n.preferredUsername,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.password,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmPasswordCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.confirmPassword,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(() => _step = 1),
              child: Text(l10n.back),
            ),
            FilledButton(
              onPressed: () => _completeSetup(l10n),
              child: Text(l10n.createVault),
            ),
          ],
        ),
      ],
    );
  }

  void _completeSetup(AppLocalizations l10n) {
    final pw = _passwordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;

    if (pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.passwordCannotBeEmpty)),
      );
      return;
    }

    if (pw != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.passwordsDoNotMatch)),
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
        SnackBar(content: Text(l10n.failedToSetPassword)),
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
