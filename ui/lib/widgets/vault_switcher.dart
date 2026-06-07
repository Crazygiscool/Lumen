import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

class VaultSwitcher extends ConsumerStatefulWidget {
  final VoidCallback onChanged;

  const VaultSwitcher({super.key, required this.onChanged});

  @override
  ConsumerState<VaultSwitcher> createState() => _VaultSwitcherState();
}

class _VaultSwitcherState extends ConsumerState<VaultSwitcher> {
  String _current = 'default';
  late List<String> _vaults;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_loaded) {
      _vaults = ref.read(lumenCoreProvider).listVaults();
      if (!_vaults.contains('default')) {
        _vaults.insert(0, 'default');
      }
      _loaded = true;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: DropdownButtonFormField<String>(
        initialValue: _vaults.contains(_current) ? _current : _vaults.first,
        isExpanded: true,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.folder, size: 18, color: cs.primary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        items: _vaults.map((v) => DropdownMenuItem(
          value: v,
          child: Text(v, style: TextStyle(color: cs.onSurface, fontSize: 14)),
        )).toList(),
        onChanged: (val) {
          if (val == null || val == _current) return;
          final ok = ref.read(lumenCoreProvider).openVault(val);
          if (ok) {
            setState(() => _current = val);
            widget.onChanged();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to open vault "$val"')),
            );
          }
        },
      ),
    );
  }
}
