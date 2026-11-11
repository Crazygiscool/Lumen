import 'package:flutter/material.dart';

/// A piece of a highlighted snippet.
class HighlightSpan {
  const HighlightSpan(this.text, {this.matched = false});

  final String text;
  final bool matched;
}

/// Splits a search snippet into its matched and unmatched parts.
///
/// The core returns snippets as HTML with `<b>` around the matched terms, so
/// the terms are highlighted without running the query a second time.
List<HighlightSpan> parseSnippet(String snippet) {
  if (snippet.isEmpty) return const [];

  final spans = <HighlightSpan>[];
  final pattern = RegExp(r'<b>(.*?)</b>', dotAll: true);
  var cursor = 0;

  for (final match in pattern.allMatches(snippet)) {
    if (match.start > cursor) {
      spans.add(HighlightSpan(snippet.substring(cursor, match.start)));
    }
    spans.add(HighlightSpan(match.group(1) ?? '', matched: true));
    cursor = match.end;
  }

  if (cursor < snippet.length) {
    spans.add(HighlightSpan(snippet.substring(cursor)));
  }

  return spans;
}

/// Renders a search snippet with its matched terms highlighted.
class HighlightedSnippet extends StatelessWidget {
  const HighlightedSnippet(this.snippet, {super.key, this.style});

  final String snippet;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final spans = parseSnippet(snippet);

    if (spans.isEmpty) return const SizedBox.shrink();

    return Text.rich(
      TextSpan(
        children: [
          for (final span in spans)
            TextSpan(
              text: span.text,
              style: span.matched
                  ? base.copyWith(
                      fontWeight: FontWeight.w700,
                      backgroundColor:
                          Theme.of(context).colorScheme.primary.withValues(
                            alpha: 0.22,
                          ),
                    )
                  : base,
            ),
        ],
      ),
    );
  }
}
