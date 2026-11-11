// Helpers for the `[[wikilink]]` syntax.
//
// The app has to do three things with a wikilink: render it as a tappable
// link in the preview, offer completion while it is being typed, and
// insert it again once a target is picked.

/// The URI scheme the preview uses for wikilink markdown links.
const wikilinkScheme = 'lumen-wikilink:';

final RegExp _wikilinkPattern = RegExp(r'\[\[([^[\]|]+)(?:\|([^[\]|]+))?\]\]');

/// The markdown link a wikilink is rewritten to.
///
/// Markdown has no inline syntax for `[[...]]`, so the preview rewrites each
/// link into a normal markdown link with a private URI scheme. That keeps the
/// renderer, the link styling and the tap handling in the hands of the
/// markdown package.
String wikilinkUri(String target) =>
    '$wikilinkScheme${Uri.encodeComponent(target)}';

/// The link target behind a wikilink markdown URI, or `null` if the URI is
/// not a wikilink.
String? wikilinkTargetFromUri(String? uri) {
  if (uri == null || !uri.startsWith(wikilinkScheme)) return null;
  return Uri.decodeComponent(uri.substring(wikilinkScheme.length));
}

/// Rewrites every wikilink in a Markdown body into a markdown link.
///
/// Fenced code blocks and inline code are left alone — a wikilink shown as
/// an example should stay an example.
String rewriteWikilinks(String markdown) {
  final out = StringBuffer();
  var inFence = false;
  String? fenceMarker;

  for (final line in markdown.split('\n')) {
    final trimmed = line.trimLeft();
    final marker = trimmed.startsWith('```')
        ? '```'
        : (trimmed.startsWith('~~~') ? '~~~' : null);

    if (marker != null) {
      if (!inFence) {
        inFence = true;
        fenceMarker = marker;
      } else if (fenceMarker == marker) {
        inFence = false;
        fenceMarker = null;
      }
      out.writeln(line);
      continue;
    }

    if (inFence) {
      out.writeln(line);
      continue;
    }

    out.writeln(_rewriteInline(line));
  }

  return out.toString();
}

/// Rewrites the wikilinks in a single line, skipping inline code spans.
String _rewriteInline(String line) {
  final out = StringBuffer();
  var cursor = 0;

  for (final match in RegExp(r'`[^`]*`').allMatches(line)) {
    out.write(_replaceWikilinks(line.substring(cursor, match.start)));
    out.write(match.group(0));
    cursor = match.end;
  }
  out.write(_replaceWikilinks(line.substring(cursor)));

  return out.toString();
}

String _replaceWikilinks(String text) => text.replaceAllMapped(
  _wikilinkPattern,
  (match) {
    final target = match.group(1)!.trim();
    if (target.isEmpty) return match.group(0)!;
    final display = match.group(2)?.trim();
    final label = (display == null || display.isEmpty) ? target : display;
    return '[$label](${wikilinkUri(target)})';
  },
);

/// The wikilink the caret is currently inside, if any.
class ActiveWikilink {
  const ActiveWikilink({
    required this.start,
    required this.end,
    required this.query,
  });

  /// Index of the opening `[[`.
  final int start;

  /// Index of the caret.
  final int end;

  /// The text typed after the `[[`.
  final String query;
}

/// Finds the wikilink the caret sits in.
///
/// Returns `null` when the caret is not inside a `[[...]]`, so the completion
/// popup can be hidden.
ActiveWikilink? activeWikilink(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;

  final before = text.substring(0, cursor);
  final open = before.lastIndexOf('[[');
  if (open < 0) return null;

  // A `]]` between the `[[` and the caret means the link is already closed.
  if (before.indexOf(']]', open) >= 0) return null;

  final query = before.substring(open + 2);
  // A link cannot span lines, and a nested `[[` is not a link either.
  if (query.contains('\n') || query.contains('[[')) return null;

  return ActiveWikilink(start: open, end: cursor, query: query);
}

/// Replaces the wikilink being typed with a finished one.
String insertWikilink(
  String text,
  ActiveWikilink active, {
  required String target,
  String? display,
}) {
  final link = (display == null || display.isEmpty)
      ? '[[$target]]'
      : '[[$target|$display]]';
  return text.replaceRange(active.start, active.end, link);
}

/// The note title a link target refers to.
///
/// The core normalizes targets to lower-case, hyphenated file names; this
/// turns one back into something readable.
String prettifyTarget(String target) {
  final stem = target.endsWith('.md')
      ? target.substring(0, target.length - 3)
      : target;
  return stem
      .split('-')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
