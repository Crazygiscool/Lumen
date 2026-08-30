import 'package:flutter/material.dart';

/// Shared passphrase dialog used by Journal, Tank, Vault, and Onboarding.
///
/// Two entry points:
///  * [ask] — collects a passphrase (optionally with a confirm field) and
///    returns it. No backend call. Ideal for create flows that call the store
///    afterwards.
///  * [showUnlock] — collects a passphrase and calls [onSubmit], rendering any
///    thrown error inline so the dialog stays open on a wrong passphrase.
class PassphraseDialog {
  PassphraseDialog._();

  /// Prompts for a passphrase and returns it, or null when cancelled.
  /// When [confirm] is true a second "Confirm passphrase" field is shown and
  /// both must match before the dialog completes.
  static Future<String?> ask(
    BuildContext context, {
    required String title,
    String label = 'Passphrase',
    String? helper,
    bool confirm = false,
    String actionLabel = 'Continue',
    String? path,
    int minLength = 8,
  }) {
    final ctl = TextEditingController();
    final ctl2 = TextEditingController();
    String? error;

    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) {
          void submit() {
            final a = ctl.text;
            if (a.isEmpty) return;
            if (a.length < minLength) {
              setState(() => error = 'Passphrase must be at least $minLength characters.');
              return;
            }
            if (confirm && a != ctl2.text) {
              setState(() => error = 'Passphrases do not match.');
              return;
            }
            Navigator.pop(c, a);
          }

          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (path != null) ...[
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Geist Mono',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: ctl,
                  autofocus: true,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: label,
                    helperText: helper,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => submit(),
                ),
                if (confirm) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctl2,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm passphrase',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: submit, child: Text(actionLabel)),
            ],
          );
        },
      ),
    ).whenComplete(() {
      ctl.dispose();
      ctl2.dispose();
    });
  }

  /// Prompts for a passphrase and runs [onSubmit], which may throw.
  /// Errors thrown are rendered inline and the dialog stays open.
  /// Returns true only after [onSubmit] completed without throwing.
  static Future<bool> showUnlock(
    BuildContext context, {
    required String title,
    String label = 'Passphrase',
    String? helper,
    required Future<void> Function(String pass) onSubmit,
    String? path,
    String actionLabel = 'Unlock',
  }) {
    final ctl = TextEditingController();
    String? error;
    var busy = false;

    return showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) {
          Future<void> submit() async {
            final a = ctl.text;
            if (a.isEmpty) return;
            setState(() {
              busy = true;
              error = null;
            });
            try {
              await onSubmit(a);
              if (c.mounted) Navigator.pop(c, true);
            } catch (e) {
              setState(() {
                busy = false;
                error = e.toString();
              });
            }
          }

          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (path != null) ...[
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Geist Mono',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: ctl,
                  autofocus: true,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: label,
                    helperText: helper,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => submit(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(actionLabel),
              ),
            ],
          );
        },
      ),
    ).then((ok) => ok == true, onError: (_) => false).whenComplete(ctl.dispose);
  }
}
