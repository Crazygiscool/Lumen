import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/glass.dart';
import '../../theme/lumen_colors.dart';
import '../command_palette.dart';
import '../web/ad_block_service.dart';
import '../web/web_controller.dart';
import '../web/web_controllers.dart';
import 'tab_model.dart';
import 'tabs_provider.dart';

class AddressBar extends ConsumerStatefulWidget {
  const AddressBar({super.key, required this.focusNode});

  final FocusNode focusNode;

  @override
  ConsumerState<AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends ConsumerState<AddressBar> {
  late final TextEditingController _ctl;
  bool _focused = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(
      text: ref.read(tabsProvider).active?.url ?? '',
    );
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    _ctl.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  void _submit(String value) {
    _editing = false;
    final v = value.trim();
    if (v.isEmpty) return;
    ref.read(tabsProvider.notifier).navigate(v);
    widget.focusNode.unfocus();
  }

  void _dismiss() {
    _editing = false;
    widget.focusNode.unfocus();
  }

  bool _isLikelyWeb(String q) {
    final lower = q.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('www.') ||
        lower.startsWith('localhost')) {
      return true;
    }
    return RegExp(r'[a-z0-9-]+\.[a-z]{2,}').hasMatch(lower);
  }

  /// The live embedded webview controller for the active tab, if any.
  LumenWebViewController? _activeWeb() {
    final activeId = ref.read(tabsProvider).active?.id;
    if (activeId == null) return null;
    return WebControllers.instance[activeId];
  }

  Widget _navButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onPressed : null,
    );
  }

  /// The ad-block shield: reflects the active web tab's exempt state and
  /// blocked-request count, and offers per-site pause / global controls.
  Widget _shield({required LumenTab? active}) {
    final ad = ref.watch(adBlockProvider);
    final web = _activeWeb();
    final host = web?.host;
    final isWeb = active?.kind == TabKind.web;
    final exempt = host != null && ad.exemptHosts.contains(host);
    final blocked = web?.blockedCount.value ?? 0;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: PopupMenuButton<String>(
        tooltip: isWeb ? 'Ad blocking for ${host ?? 'this site'}' : 'Ad blocking',
        enabled: isWeb && ad.enabled,
        icon: Badge.count(
          count: blocked,
          isLabelVisible: blocked > 0 && isWeb,
          child: Icon(
            exempt || !ad.enabled ? Icons.shield_outlined : Icons.shield,
            size: 16,
            color: exempt || !ad.enabled
                ? LumenColors.of(context).onSurfaceVariant
                : LumenColors.of(context).primary,
          ),
        ),
        onSelected: (v) {
          final notifier = ref.read(adBlockProvider.notifier);
          switch (v) {
            case 'exempt':
              if (host != null) notifier.toggleExempt(host);
            case 'disable':
              notifier.toggle(false);
            case 'refresh':
              notifier.refresh(force: true);
          }
        },
        itemBuilder: (context) => [
          if (host != null)
            PopupMenuItem(
              value: 'exempt',
              child: Text(
                exempt
                    ? 'Resume blocking on $host'
                    : 'Pause blocking on $host',
              ),
            ),
          const PopupMenuItem(value: 'disable', child: Text('Disable ad blocking')),
          const PopupMenuItem(value: 'refresh', child: Text('Update filter lists')),
          if (ad.status != AdBlockStatus.ready)
            const PopupMenuItem(
              enabled: false,
              child: Text('Filter lists unavailable',
                  style: TextStyle(color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tabsProvider, (prev, next) {
      final u = next.active?.url ?? '';
      if (!_editing && _ctl.text != u) {
        _ctl.value = TextEditingValue(
          text: u,
          selection: TextSelection.collapsed(offset: u.length),
        );
      }
    });

    final t = LumenColors.of(context);
    final tabs = ref.watch(tabsProvider);
    final notifier = ref.read(tabsProvider.notifier);
    final active = tabs.active;
    final web = _activeWeb();
    final suggestions = _suggestions();
    final isWeb = active?.kind == TabKind.web;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: Glass(
            blurSigma: 14,
            radius: 0,
            fill: t.surfaceContainer,
            border: false,
            child: Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (web != null && isWeb)
                      ValueListenableBuilder<bool>(
                        valueListenable: web.canGoBack,
                        builder: (_, v, _) => IconButton(
                          tooltip: 'Back (Alt+Left)',
                          icon: const Icon(Icons.arrow_back, size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: v ? notifier.back : null,
                        ),
                      )
                    else
                      _navButton(
                        icon: Icons.arrow_back,
                        tooltip: 'Back (Alt+Left)',
                        enabled: active?.canGoBack == true,
                        onPressed: notifier.back,
                      ),
                    if (web != null && isWeb)
                      ValueListenableBuilder<bool>(
                        valueListenable: web.canGoForward,
                        builder: (_, v, _) => IconButton(
                          tooltip: 'Forward (Alt+Right)',
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: v ? notifier.forward : null,
                        ),
                      )
                    else
                      _navButton(
                        icon: Icons.arrow_forward,
                        tooltip: 'Forward (Alt+Right)',
                        enabled: active?.canGoForward == true,
                        onPressed: notifier.forward,
                      ),
                    _navButton(
                      icon: Icons.refresh,
                      tooltip: 'Reload (Ctrl+R)',
                      enabled: active != null,
                      onPressed: notifier.reload,
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: t.surfaceLow,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: t.hairline, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bolt_outlined,
                          size: 14,
                          color: t.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _ctl,
                            focusNode: widget.focusNode,
                            onChanged: (_) => setState(() => _editing = true),
                            onSubmitted: _submit,
                            textInputAction: TextInputAction.go,
                            decoration: const InputDecoration(
                              hintText:
                                  'lumen://pages, a file path, or any website…',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 0,
                              ),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _shield(active: active),
                IconButton(
                  tooltip: 'New tab (Ctrl+T)',
                  icon: const Icon(Icons.library_add_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => notifier.newTab(),
                ),
                IconButton(
                  tooltip: 'Command palette (Ctrl+P)',
                  icon: const Icon(Icons.keyboard_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      ref.read(commandPaletteProvider.notifier).open(),
                ),
              ],
            ),
          ),
        ),
        if (suggestions.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: t.surfaceContainer,
              border: Border(bottom: BorderSide(color: t.hairline, width: 1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: suggestions,
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }

  List<Widget> _suggestions() {
    if (!_focused) return const [];
    final q = _ctl.text.trim();
    final ql = q.toLowerCase();
    final notifier = ref.read(tabsProvider.notifier);
    final items = <Widget>[];

    if (q.isEmpty) {
      items.add(
        _sugg(
          icon: Icons.window,
          title: 'New tab',
          subtitle: 'lumen://newtab',
          onTap: () => _submit('lumen://newtab'),
        ),
      );
    }

    for (final s in LumenSection.values) {
      final url = 'lumen://${s.pathName}';
      if (q.isEmpty || url.contains(ql) || s.title.toLowerCase().contains(ql)) {
        final section = s;
        items.add(
          _sugg(
            icon: s.icon,
            title: s.title,
            subtitle: url,
            onTap: () {
              _dismiss();
              ref.read(tabsProvider.notifier).activatePage(section);
            },
          ),
        );
      }
    }

    if (q.isNotEmpty) {
      final web = _isLikelyWeb(q);
      items.insert(
        0,
        _sugg(
          icon: web ? Icons.travel_explore : Icons.search,
          title: web ? 'Open “$q” in your browser' : 'Search the web for “$q”',
          subtitle: web ? q : 'duckduckgo',
          onTap: () => _submit(q),
        ),
      );
    }

    final recent = <String, String>{};
    final tabs = ref.read(tabsProvider);
    for (final tab in tabs.tabs) {
      recent[tab.url] = tab.title;
      for (final h in tab.history) {
        recent[h.url] = h.title;
      }
    }
    var added = 0;
    for (final e in recent.entries) {
      if (added >= 5) break;
      final u = e.key.toLowerCase();
      if (q.isEmpty || u.contains(ql) || e.value.toLowerCase().contains(ql)) {
        final url = e.key;
        final title = e.value;
        items.add(
          _sugg(
            icon: Icons.history,
            title: title,
            subtitle: url,
            onTap: () {
              _dismiss();
              notifier.navigate(url);
            },
          ),
        );
        added++;
      }
    }

    return items;
  }

  Widget _sugg({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final t = LumenColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 15, color: t.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: t.onSurface),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: t.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
