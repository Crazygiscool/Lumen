import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/lumen_colors.dart';
import '../theme/glass.dart';

class GraphScreen extends ConsumerWidget {
  const GraphScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultProvider);
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Glass(
            blurSigma: 14,
            radius: 0,
            fill: LumenColors.of(context).surfaceContainer,
            border: false,
            child: Row(
              children: [
                Icon(
                  Icons.hub_outlined,
                  size: 16,
                  color: LumenColors.of(context).primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'GRAPH',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: LumenColors.of(context).outline,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Filesystem + vault backlink graph',
                    style: TextStyle(
                      fontSize: 12,
                      color: LumenColors.of(context).onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.hub_outlined,
                  size: 56,
                  color: LumenColors.of(context).outlineVariant,
                ),
                SizedBox(height: 16),
                Text(
                  'Graph view is on the roadmap.',
                  style: TextStyle(
                    fontSize: 16,
                    color: LumenColors.of(context).onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  vault.unlocked
                      ? 'Vault unlocked — backlink data ready when the graph ships.'
                      : 'Unlock the vault to enable the backlink layer.',
                  style: TextStyle(
                    fontSize: 12,
                    color: LumenColors.of(context).onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
