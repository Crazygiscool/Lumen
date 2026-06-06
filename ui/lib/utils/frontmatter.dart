class ParsedEntry {
  final Map<String, String> metadata;
  final String body;

  ParsedEntry({required this.metadata, required this.body});
}

ParsedEntry parseFrontmatter(String text) {
  if (!text.startsWith('---\n')) {
    return ParsedEntry(metadata: {}, body: text);
  }

  final end = text.indexOf('\n---', 4);
  if (end == -1) {
    return ParsedEntry(metadata: {}, body: text);
  }

  final front = text.substring(4, end);
  final body = text.substring(end + 5);

  final metadata = <String, String>{};
  for (final line in front.split('\n')) {
    final colon = line.indexOf(':');
    if (colon > 0) {
      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      if (key.isNotEmpty) {
        metadata[key] = value;
      }
    }
  }

  return ParsedEntry(metadata: metadata, body: body.trim());
}
