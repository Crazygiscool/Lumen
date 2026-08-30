import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../files/folder_picker_dialog.dart';
import '../journal/journal_provider.dart';
import '../state/providers.dart';
import '../theme/lumen_colors.dart';

/// First-run "Getting Started" wizard: welcome, define goals, and set up the
/// two encrypted stores — the knowledge base (which *is* the Lumen vault) and
/// the journal (which may share the vault folder with its own passphrase).
/// Re-launchable from Settings; lives as a revisitable tab.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _page = PageController();
  int _step = 0;

  final _goal = TextEditingController();
  final List<String> _goals = [];

  String _vaultPath = '';
  String _vaultPass = '';
  String _vaultPassConfirm = '';
  bool _vaultReady = false;

  bool _shareVaultPath = true;
  String _journalPath = '';
  String _journalPass = '';
  String _journalPassConfirm = '';
  bool _journalReady = false;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _page.dispose();
    _goal.dispose();
    super.dispose();
  }

  static const _totalSteps = 5;

  String get _effectiveJournalPath =>
      _shareVaultPath ? _vaultPath : _journalPath;

  void _next() {
    if (_step < _totalSteps - 1) {
      _page.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _back() {
    _page.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    setState(() => _step--);
  }

  /// Setup steps (vault, journal) run their creation, then advance on success.
  Future<void> _handleNext() async {
    if (_step == 2) {
      await _setupVault();
      if (_vaultReady && mounted) _next();
      return;
    }
    if (_step == 3) {
      await _setupJournal();
      if (_journalReady && mounted) _next();
      return;
    }
    _next();
  }

  Future<void> _finish() async {
    final notifier = ref.read(settingsProvider.notifier);
    if (_vaultPath.isNotEmpty) notifier.setVaultPath(_vaultPath);
    if (_effectiveJournalPath.isNotEmpty) {
      notifier.setJournalVaultPath(_effectiveJournalPath);
    }
    ref.read(onboardingProvider.notifier).complete(
      goals: [for (final g in _goals) Goal(text: g)],
    );
  }

  Future<void> _pickVault() async {
    final dir = await showFolderPicker(
      context,
      title: 'Lumen vault / knowledge base',
    );
    if (dir != null) setState(() => _vaultPath = dir);
  }

  Future<void> _pickJournal() async {
    final dir = await showFolderPicker(context, title: 'Journal folder');
    if (dir != null) setState(() => _journalPath = dir);
  }

  /// Creates (or unlocks, if it already exists) and unlocks a store.
  Future<void> _ensureStore(
    String store,
    String path,
    String pass,
  ) async {
    final notifier = ref.read(
      store == 'journal' ? journalVaultProvider.notifier : vaultProvider.notifier,
    );
    try {
      await notifier.create(path, pass);
    } catch (e) {
      if (e.toString().contains('already exists')) {
        await notifier.unlock(path, pass);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _setupVault() async {
    if (_vaultPath.isEmpty) {
      setState(() => _error = 'Choose a folder for your vault.');
      return;
    }
    if (_vaultPass.length < 8) {
      setState(() => _error = 'Passphrase must be at least 8 characters.');
      return;
    }
    if (_vaultPass != _vaultPassConfirm) {
      setState(() => _error = 'Passphrases do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _ensureStore('vault', _vaultPath, _vaultPass);
      if (mounted) setState(() => _vaultReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setupJournal() async {
    final path = _effectiveJournalPath;
    if (path.isEmpty) {
      setState(() => _error = 'Choose a folder for your journal.');
      return;
    }
    if (_journalPass.length < 8) {
      setState(() => _error = 'Passphrase must be at least 8 characters.');
      return;
    }
    if (_journalPass != _journalPassConfirm) {
      setState(() => _error = 'Passphrases do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _ensureStore('journal', path, _journalPass);
      final journal = ref.read(journalServiceProvider);
      await journal.recordEntry();
      await ref.read(journalVaultServiceProvider).writeText(
        'projects.json',
        const JsonEncoder.withIndent('  ').convert(const []),
      );
      if (mounted) setState(() => _journalReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _nextLabel => _step == _totalSteps - 1 ? 'Get started' : 'Continue';

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return ColoredBox(
      color: t.surfaceContainer,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: t.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Getting started',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: t.onSurface,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () =>
                            ref.read(onboardingProvider.notifier).skip(),
                        child: const Text('Skip for now'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        const SizedBox(width: 24),
                        for (var i = 0; i < _totalSteps; i++)
                          Expanded(
                            child: Container(
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: i <= _step ? t.primary : t.hairline,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        const SizedBox(width: 24),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 380,
                    child: PageView(
                      controller: _page,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        const _IntroPage(),
                        _GoalsPage(
                          t: t,
                          goals: _goals,
                          controller: _goal,
                          onAdd: () {
                            final v = _goal.text.trim();
                            if (v.isEmpty) return;
                            setState(() {
                              _goals.add(v);
                              _goal.clear();
                            });
                          },
                          onRemove: (g) => setState(() => _goals.remove(g)),
                        ),
                        _VaultPage(
                          t: t,
                          path: _vaultPath,
                          pass: _vaultPass,
                          passConfirm: _vaultPassConfirm,
                          ready: _vaultReady,
                          error: _error,
                          busy: _busy,
                          onPick: _pickVault,
                          onPass: (v) => setState(() => _vaultPass = v),
                          onPassConfirm: (v) =>
                              setState(() => _vaultPassConfirm = v),
                        ),
                        _JournalPage(
                          t: t,
                          shareVaultPath: _shareVaultPath,
                          sharedWith: _vaultPath,
                          path: _journalPath,
                          pass: _journalPass,
                          passConfirm: _journalPassConfirm,
                          ready: _journalReady,
                          error: _error,
                          busy: _busy,
                          onToggleShare: (v) =>
                              setState(() => _shareVaultPath = v),
                          onPick: _pickJournal,
                          onPass: (v) => setState(() => _journalPass = v),
                          onPassConfirm: (v) =>
                              setState(() => _journalPassConfirm = v),
                        ),
                        _DonePage(
                          t: t,
                          vaultPath: _vaultPath,
                          journalPath: _effectiveJournalPath,
                          goals: _goals,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                    child: Row(
                      children: [
                        if (_step > 0)
                          TextButton(onPressed: _back, child: const Text('Back')),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _busy ? null : _handleNext,
                          icon: Icon(
                            _step == _totalSteps - 1
                                ? Icons.done
                                : Icons.arrow_forward,
                            size: 18,
                          ),
                          label: Text(_nextLabel),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _IntroPage extends StatelessWidget {
  const _IntroPage();

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.auto_awesome, color: t.primary, size: 34),
          ),
          const SizedBox(height: 18),
          Text(
            'Make Lumen yours',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Lumen is your personal workbench: an encrypted knowledge base '
            'for what you learn, and a private journal for your day.\n\n'
            'This takes about a minute.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: t.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalsPage extends StatelessWidget {
  const _GoalsPage({
    required this.t,
    required this.goals,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });
  final LumenPalette t;
  final List<String> goals;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What are your current goals?',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: t.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'These anchor your projects and journaling.',
            style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'e.g. Ship my side project',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintStyle: TextStyle(color: t.onSurfaceVariant),
                  ),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Add goal',
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                for (final g in goals)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, size: 16, color: t.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(g, style: const TextStyle(fontSize: 13.5)),
                        ),
                        InkWell(
                          onTap: () => onRemove(g),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: t.onSurfaceVariant,
                          ),
                        ),
                      ],
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

class _VaultPage extends StatelessWidget {
  const _VaultPage({
    required this.t,
    required this.path,
    required this.pass,
    required this.passConfirm,
    required this.ready,
    required this.error,
    required this.busy,
    required this.onPick,
    required this.onPass,
    required this.onPassConfirm,
  });
  final LumenPalette t;
  final String path;
  final String pass;
  final String passConfirm;
  final bool ready;
  final String? error;
  final bool busy;
  final VoidCallback onPick;
  final ValueChanged<String> onPass;
  final ValueChanged<String> onPassConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lumen vault · your knowledge base',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: t.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Everything in this folder is encrypted on disk (Argon2id + '
            'AES-256-GCM). Only the metadata you want to show stays plain.',
            style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          _PathField(t: t, path: path, hint: 'Choose your vault folder…', onPick: onPick),
          const SizedBox(height: 12),
          TextField(
            obscureText: true,
            onChanged: onPass,
            decoration: const InputDecoration(
              labelText: 'Passphrase',
              hintText: 'At least 8 characters',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            obscureText: true,
            onChanged: onPassConfirm,
            decoration: const InputDecoration(
              labelText: 'Confirm passphrase',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(fontSize: 12, color: t.error)),
          ],
          const Spacer(),
          Row(
            children: [
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (ready)
                Icon(Icons.check_circle, size: 18, color: t.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ready
                      ? 'Vault created and unlocked for this session.'
                      : 'Continue to create and unlock your encrypted vault.',
                  style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JournalPage extends StatelessWidget {
  const _JournalPage({
    required this.t,
    required this.shareVaultPath,
    required this.sharedWith,
    required this.path,
    required this.pass,
    required this.passConfirm,
    required this.ready,
    required this.error,
    required this.busy,
    required this.onToggleShare,
    required this.onPick,
    required this.onPass,
    required this.onPassConfirm,
  });
  final LumenPalette t;
  final bool shareVaultPath;
  final String sharedWith;
  final String path;
  final String pass;
  final String passConfirm;
  final bool ready;
  final String? error;
  final bool busy;
  final ValueChanged<bool> onToggleShare;
  final VoidCallback onPick;
  final ValueChanged<String> onPass;
  final ValueChanged<String> onPassConfirm;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your journal',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: t.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Journal entries are written once a day. Your journal keeps its '
            'own passphrase, so it stays private even if you share the folder.',
            style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Use the same folder as my vault'),
            subtitle: sharedWith.isEmpty
                ? null
                : Text(
                    sharedWith,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Geist Mono',
                      color: t.onSurfaceVariant,
                    ),
                  ),
            value: shareVaultPath,
            onChanged: onToggleShare,
          ),
          if (!shareVaultPath) ...[
            const SizedBox(height: 8),
            _PathField(t: t, path: path, hint: 'Choose a folder for your journal…', onPick: onPick),
          ],
          const SizedBox(height: 12),
          TextField(
            obscureText: true,
            onChanged: onPass,
            decoration: const InputDecoration(
              labelText: 'Journal passphrase',
              hintText: 'At least 8 characters',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            obscureText: true,
            onChanged: onPassConfirm,
            decoration: const InputDecoration(
              labelText: 'Confirm passphrase',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(fontSize: 12, color: t.error)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (ready)
                Icon(Icons.check_circle, size: 18, color: t.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ready
                      ? 'Journal created and unlocked for this session.'
                      : 'A welcome entry is written into today’s journal.',
                  style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonePage extends StatelessWidget {
  const _DonePage({
    required this.t,
    required this.vaultPath,
    required this.journalPath,
    required this.goals,
  });
  final LumenPalette t;
  final String vaultPath;
  final String journalPath;
  final List<String> goals;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You’re all set',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _summaryRow(t, Icons.lock_outline, 'Vault / knowledge base', vaultPath),
          const SizedBox(height: 10),
          _summaryRow(t, Icons.book_outlined, 'Journal', journalPath),
          const SizedBox(height: 16),
          Text(
            goals.isEmpty
                ? 'Head to Home, Vault or Projects to begin.'
                : '${goals.length} goal${goals.length == 1 ? '' : 's'} set. '
                      'Head to Home, Vault or Projects to begin.',
            style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(LumenPalette t, IconData icon, String label, String path) {
    return Row(
      children: [
        Icon(icon, size: 18, color: t.primary),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            path.isEmpty ? '—' : path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Geist Mono',
              color: t.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _PathField extends StatelessWidget {
  const _PathField({
    required this.t,
    required this.path,
    required this.hint,
    required this.onPick,
  });
  final LumenPalette t;
  final String path;
  final String hint;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: t.hairline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              path.isEmpty ? hint : path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontFamily: 'Geist Mono',
                color: path.isEmpty ? t.onSurfaceVariant : t.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('Browse'),
        ),
      ],
    );
  }
}