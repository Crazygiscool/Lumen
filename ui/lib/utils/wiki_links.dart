final _wikiRegex = RegExp(r'\[\[([^\]]+)\]\]');

/// Converts [[wiki links]] to Markdown links with a lumen:// scheme.
String renderWikiLinks(String text) {
  return text.replaceAllMapped(_wikiRegex, (m) {
    final target = m[1]!;
    return '[$target](lumen://entry/$target)';
  });
}

/// Parse a lumen:// URI tapped in a Markdown widget.
/// Returns the target string (e.g., entry ID or display_title), or null.
String? parseWikiLinkTap(String text) {
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'lumen') return null;
  if (uri.host == 'entry') {
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  }
  return null;
}
