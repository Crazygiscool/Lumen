import 'package:flutter/foundation.dart';

import '../ffi/lumen_ffi.dart';

/// A hit from the full-text index.
///
/// [snippet] is HTML with `<b>` around the matched terms, so it can be
/// highlighted without re-running the query.
@immutable
class KbSearchHit {
  const KbSearchHit({
    required this.path,
    required this.title,
    required this.snippet,
    required this.score,
  });

  final String path;
  final String title;
  final String snippet;
  final double score;

  factory KbSearchHit.fromJson(Map<String, dynamic> j) => KbSearchHit(
    path: j['path'] as String? ?? '',
    title: j['title'] as String? ?? '',
    snippet: j['snippet'] as String? ?? '',
    score: (j['score'] as num?)?.toDouble() ?? 0,
  );
}

/// A `[[wikilink]]` found in a note.
@immutable
class KbWikilink {
  const KbWikilink({
    required this.target,
    required this.display,
    required this.start,
    required this.end,
  });

  /// The normalized target (lower-case, hyphenated, `.md` suffix).
  final String target;

  /// The display text from `[[target|display]]`, if any.
  final String? display;

  /// Byte offsets of the whole `[[...]]` in the source body.
  final int start;
  final int end;

  factory KbWikilink.fromJson(Map<String, dynamic> j) => KbWikilink(
    target: j['target'] as String? ?? '',
    display: j['display'] as String?,
    start: (j['start'] as num?)?.toInt() ?? 0,
    end: (j['end'] as num?)?.toInt() ?? 0,
  );
}

/// A command registered in the command palette.
@immutable
class KbCommand {
  const KbCommand({
    required this.id,
    required this.title,
    this.description,
    this.keywords = const [],
    this.source = 'builtin',
  });

  /// Unique command id (e.g. `journal.openDailyNote`).
  final String id;

  /// Human-readable title shown in the palette.
  final String title;

  /// Optional description shown as a subtitle.
  final String? description;

  /// Keywords for fuzzy matching.
  final List<String> keywords;

  /// Source of the command: `builtin` or a plugin id.
  final String source;

  factory KbCommand.fromJson(Map<String, dynamic> j) => KbCommand(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    keywords: (j['keywords'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(),
    source: j['source'] as String? ?? 'builtin',
  );
}

/// A note's YAML frontmatter.
///
/// Fields the app does not know about are kept in [custom] and written back
/// untouched.
@immutable
class KbFrontmatter {
  const KbFrontmatter({
    this.tags = const [],
    this.aliases = const [],
    this.title,
    this.date,
    this.cssClass,
    this.custom = const {},
  });

  final List<String> tags;
  final List<String> aliases;
  final String? title;

  /// An ISO date (`YYYY-MM-DD`), if the note carries one.
  final String? date;
  final String? cssClass;
  final Map<String, dynamic> custom;

  static const _known = {'tags', 'aliases', 'title', 'date', 'cssclass'};

  factory KbFrontmatter.fromJson(Map<String, dynamic> j) {
    final custom = <String, dynamic>{};
    for (final entry in j.entries) {
      if (!_known.contains(entry.key)) custom[entry.key] = entry.value;
    }
    return KbFrontmatter(
      tags: [for (final t in (j['tags'] as List<dynamic>? ?? const [])) '$t'],
      aliases: [
        for (final a in (j['aliases'] as List<dynamic>? ?? const [])) '$a',
      ],
      title: j['title'] as String?,
      date: j['date'] as String?,
      cssClass: j['cssclass'] as String?,
      custom: custom,
    );
  }

  Map<String, dynamic> toJson() => {
    'tags': tags,
    'aliases': aliases,
    'title': ?title,
    'date': ?date,
    'cssclass': ?cssClass,
    ...custom,
  };

  KbFrontmatter copyWith({
    List<String>? tags,
    List<String>? aliases,
    String? title,
    String? date,
    String? cssClass,
    Map<String, dynamic>? custom,
  }) => KbFrontmatter(
    tags: tags ?? this.tags,
    aliases: aliases ?? this.aliases,
    title: title ?? this.title,
    date: date ?? this.date,
    cssClass: cssClass ?? this.cssClass,
    custom: custom ?? this.custom,
  );

  /// Whether the note carries no metadata at all.
  bool get isEmpty =>
      tags.isEmpty &&
      aliases.isEmpty &&
      title == null &&
      date == null &&
      cssClass == null &&
      custom.isEmpty;
}

/// The daily note template: the file it lives in and what it holds.
@immutable
class KbTemplate {
  const KbTemplate({required this.path, required this.content});

  /// Where the template file lives.
  final String path;

  /// The template text.
  final String content;

  factory KbTemplate.fromJson(Map<String, dynamic> j) => KbTemplate(
    path: j['path'] as String? ?? '',
    content: j['content'] as String? ?? '',
  );
}

/// The kind of connection between two graph nodes.
enum KbEdgeType { wikilink, backlink, tag, temporal }

/// A node in the knowledge graph — one note.
@immutable
class KbGraphNode {
  const KbGraphNode({
    required this.id,
    required this.title,
    required this.tags,
    required this.weight,
    required this.frontmatter,
  });

  /// The note's path relative to the vault root.
  final String id;
  final String title;
  final List<String> tags;

  /// Word count plus the link and backlink counts — drives the node size.
  final int weight;
  final KbFrontmatter frontmatter;

  factory KbGraphNode.fromJson(Map<String, dynamic> j) => KbGraphNode(
    id: j['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    tags: [for (final t in (j['tags'] as List<dynamic>? ?? const [])) '$t'],
    weight: (j['weight'] as num?)?.toInt() ?? 0,
    frontmatter: KbFrontmatter.fromJson(
      (j['frontmatter'] as Map<String, dynamic>? ?? const {}).cast(),
    ),
  );
}

/// A connection between two notes.
@immutable
class KbGraphEdge {
  const KbGraphEdge({
    required this.source,
    required this.target,
    required this.type,
  });

  final String source;
  final String target;
  final KbEdgeType type;

  factory KbGraphEdge.fromJson(Map<String, dynamic> j) => KbGraphEdge(
    source: j['source'] as String? ?? '',
    target: j['target'] as String? ?? '',
    type: switch (j['type'] as String? ?? 'wikilink') {
      'backlink' => KbEdgeType.backlink,
      'tag' => KbEdgeType.tag,
      'temporal' => KbEdgeType.temporal,
      _ => KbEdgeType.wikilink,
    },
  );
}

/// The graph of the whole vault.
@immutable
class KbGraphData {
  const KbGraphData({required this.nodes, required this.edges});

  final List<KbGraphNode> nodes;
  final List<KbGraphEdge> edges;

  static const empty = KbGraphData(nodes: [], edges: []);

  factory KbGraphData.fromJson(Map<String, dynamic> j) => KbGraphData(
    nodes: [
      for (final n in (j['nodes'] as List<dynamic>? ?? const []))
        KbGraphNode.fromJson((n as Map<String, dynamic>).cast()),
    ],
    edges: [
      for (final e in (j['edges'] as List<dynamic>? ?? const []))
        KbGraphEdge.fromJson((e as Map<String, dynamic>).cast()),
    ],
  );
}

/// A typed wrapper over the native knowledge-base API.
///
/// Every method goes through the `lumen_kb_call` entry point. The store is
/// named (`journal`), not a path — the core resolves the path itself.
class KbService {
  KbService(this._ffi, {this.store = 'journal'});

  final LumenFfi _ffi;

  /// Which encrypted store this service reads.
  final String store;

  Map<String, Object?> _args([Map<String, Object?> base = const {}]) => {
    ...base,
    'store': store,
  };

  Map<String, dynamic> _map(Object? data) =>
      (data as Map<String, dynamic>? ?? const {}).cast();

  List<dynamic> _list(Object? data) => data as List<dynamic>? ?? const [];

  // ---------------------------------------------------------------------------
  // Wikilinks
  // ---------------------------------------------------------------------------

  /// Every `[[wikilink]]` in a note.
  Future<List<KbWikilink>> parseWikilinks(String path) async {
    final data = _map(_ffi.kb('kb.wikilinks.parse', _args({'path': path})));
    return [
      for (final l in _list(data['links']))
        KbWikilink.fromJson((l as Map<String, dynamic>).cast()),
    ];
  }

  /// Resolve a link target to the path of the note it points at.
  ///
  /// Returns `null` when no note matches.
  Future<String?> resolveWikilink(String target) async {
    final data = _map(
      _ffi.kb('kb.wikilinks.resolve', _args({'target': target})),
    );
    final path = data['path'] as String?;
    return (path == null || path.isEmpty) ? null : path;
  }

  /// Create a note for a wikilink target that does not exist yet.
  ///
  /// Only works when `wikilinks.create_missing` is on and the note does not
  /// already exist. Returns the path of the note that was created.
  Future<String> createMissingNote(String target) async {
    final data = _map(
      _ffi.kb('kb.wikilinks.create_missing', _args({'target': target})),
    );
    return data['created'] as String? ?? '';
  }

  /// The notes that link to [path].
  Future<List<String>> backlinks(String path) async {
    final data = _map(_ffi.kb('kb.wikilinks.backlinks', _args({'path': path})));
    return [for (final b in _list(data['backlinks'])) '$b'];
  }

  /// Rebuild the backlink index from scratch.
  Future<void> rebuildBacklinkIndex() async {
    _ffi.kb('kb.wikilinks.rebuild_index', _args());
  }

  // ---------------------------------------------------------------------------
  // Command palette
  // ---------------------------------------------------------------------------

  /// Every command registered in the command palette.
  Future<List<KbCommand>> listCommands() async {
    final data = _map(_ffi.kb('kb.command.list'));
    final list = _list(data['commands']);
    return [
      for (final c in list)
        KbCommand.fromJson((c as Map<String, dynamic>? ?? const {}).cast())
    ];
  }

  /// Execute a command by id.
  ///
  /// Returns the command definition if it was found, or throws if not.
  Future<KbCommand> executeCommand(String id) async {
    final data = _map(_ffi.kb('kb.command.execute', {'id': id}));
    return KbCommand.fromJson(_map(data['command']));
  }

  // ---------------------------------------------------------------------------
  // Frontmatter
  // ---------------------------------------------------------------------------

  /// A note's frontmatter.
  Future<KbFrontmatter> getFrontmatter(String path) async {
    final data = _ffi.kb('kb.frontmatter.get', _args({'path': path}));
    return KbFrontmatter.fromJson(_map(data));
  }

  /// Replace a note's frontmatter, keeping its body.
  Future<void> setFrontmatter(String path, KbFrontmatter frontmatter) async {
    _ffi.kb(
      'kb.frontmatter.set',
      _args({'path': path, 'frontmatter': frontmatter.toJson()}),
    );
  }

  /// Splits a body into its frontmatter and the rest.
  ///
  /// This works on a body rather than a file, so an editor can read the
  /// metadata of the note it is holding in memory.
  Future<(KbFrontmatter, String)> parseFrontmatter(String body) async {
    final data = _map(_ffi.kb('kb.frontmatter.parse', {'body': body}));
    return (
      KbFrontmatter.fromJson(_map(data['frontmatter']).cast<String, dynamic>()),
      data['body'] as String? ?? '',
    );
  }

  /// Builds a body with the frontmatter in front of it.
  Future<String> serializeFrontmatter(
    KbFrontmatter frontmatter,
    String body,
  ) async {
    final data = _map(
      _ffi.kb('kb.frontmatter.serialize', {
        'frontmatter': frontmatter.toJson(),
        'body': body,
      }),
    );
    return data['text'] as String? ?? body;
  }

  /// Paths of the notes matching a frontmatter filter.
  ///
  /// [tag] matches any of a note's tags; [key] and [value] match a custom
  /// field.
  Future<List<String>> queryFrontmatter({
    String? tag,
    String? key,
    String? value,
  }) async {
    final data = _map(
      _ffi.kb(
        'kb.frontmatter.query',
        _args({'tag': ?tag, 'key': ?key, 'value': ?value}),
      ),
    );
    return [for (final p in _list(data['paths'])) '$p'];
  }

  // ---------------------------------------------------------------------------
  // Daily templates
  // ---------------------------------------------------------------------------

  /// The path of the daily note for a date (`YYYY-MM-DD.md`).
  Future<String> dailyNotePath(DateTime date) async {
    final data = _map(
      _ffi.kb('kb.template.daily_path', {
        'date_ms': date.millisecondsSinceEpoch,
      }),
    );
    return data['path'] as String? ?? '';
  }

  /// The daily template, rendered for a date.
  Future<String> renderDailyTemplate(DateTime date) async {
    final data = _map(
      _ffi.kb('kb.template.daily_render', {
        'date_ms': date.millisecondsSinceEpoch,
      }),
    );
    return data['content'] as String? ?? '';
  }

  /// Write the default daily template if none exists yet.
  Future<void> ensureTemplate() async {
    _ffi.kb('kb.template.ensure');
  }

  /// The daily template: where it lives and what it holds.
  ///
  /// The core owns the path, so the editor does not have to re-derive it.
  Future<KbTemplate> template() async {
    final data = _map(_ffi.kb('kb.template.get'));
    return KbTemplate(
      path: data['path'] as String? ?? '',
      content: data['content'] as String? ?? '',
    );
  }

  /// Save the daily template.
  Future<String> saveTemplate(String content) async {
    final data = _map(_ffi.kb('kb.template.save', {'content': content}));
    return data['path'] as String? ?? '';
  }

  /// Render a template for a date.
  ///
  /// The template is passed in rather than read from disk, so the editor can
  /// preview what the user is typing before saving it.
  Future<String> renderTemplate(String template, DateTime date) async {
    final data = _map(
      _ffi.kb('kb.template.render', {
        'template': template,
        'date_ms': date.millisecondsSinceEpoch,
      }),
    );
    return data['content'] as String? ?? '';
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  /// Bring the search index up to date.
  Future<void> initSearch() async {
    _ffi.kb('kb.search.init', _args());
  }

  /// Run a full-text query.
  Future<List<KbSearchHit>> search(String query, {int limit = 50}) async {
    final data = _map(
      _ffi.kb('kb.search.query', _args({'query': query, 'limit': limit})),
    );
    return [
      for (final h in _list(data['hits']))
        KbSearchHit.fromJson((h as Map<String, dynamic>).cast()),
    ];
  }

  /// Rebuild the whole search index.
  Future<void> reindex() async {
    _ffi.kb('kb.search.reindex', _args());
  }

  // ---------------------------------------------------------------------------
  // Graph
  // ---------------------------------------------------------------------------

  /// The whole knowledge graph.
  Future<KbGraphData> graphData() async {
    final data = _ffi.kb('kb.graph.data', _args());
    return KbGraphData.fromJson(_map(data));
  }

  /// The graph, narrowed to a set of tags and an optional text query.
  Future<KbGraphData> filterGraph({
    List<String> tags = const [],
    String? query,
  }) async {
    final args = <String, Object?>{'tags': tags};
    if (query != null) args['query'] = query;
    final data = _ffi.kb('kb.graph.filter', _args(args));
    return KbGraphData.fromJson(_map(data));
  }

  /// The notes around [center], out to [depth] hops.
  Future<KbGraphData> graphNeighborhood(String center, {int depth = 1}) async {
    final data = _ffi.kb(
      'kb.graph.neighborhood',
      _args({'center': center, 'depth': depth}),
    );
    return KbGraphData.fromJson(_map(data));
  }

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// The knowledge-base configuration.
  Future<Map<String, dynamic>> config() async {
    final data = _ffi.kb('kb.config.get');
    return _map(data);
  }

  /// Write the knowledge-base configuration.
  Future<void> setConfig(Map<String, dynamic> config) async {
    _ffi.kb('kb.config.set', {'config': config});
  }
}
