import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../theme/lumen_colors.dart';
import 'tab_model.dart';

class WebTabContent extends ConsumerStatefulWidget {
  const WebTabContent({super.key, required this.url});

  final String url;

  @override
  ConsumerState<WebTabContent> createState() => _WebTabContentState();
}

class _WebTabContentState extends ConsumerState<WebTabContent> {
  bool _opening = false;

  Future<void> _open() async {
    setState(() => _opening = true);
    await openInSystemBrowser(widget.url);
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = LumenColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: t.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.language, size: 30, color: t.primary),
            ),
            const SizedBox(height: 18),
            Text(
              'Opened in your browser',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: t.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                widget.url,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: lumenMonoFont,
                  color: t.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _opening ? null : _open,
              icon: _opening
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new, size: 18),
              label: Text(_opening ? 'Opening…' : 'Open in system browser'),
            ),
            const SizedBox(height: 12),
            Text(
              'Lumen opens external sites in your default browser.\n'
              'Back/forward return to this address.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
