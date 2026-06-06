import 'dart:convert';

import '../lumen_core.dart';

class Provenance {
  final String author;
  final String timestamp;
  final String? pluginOrigin;
  final String? feedback;

  Provenance({
    required this.author,
    required this.timestamp,
    this.pluginOrigin,
    this.feedback,
  });

  factory Provenance.fromJson(Map<String, dynamic> json) {
    return Provenance(
      author: json['author'] as String,
      timestamp: json['timestamp'] as String,
      pluginOrigin: json['plugin_origin'] as String?,
      feedback: json['feedback'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'author': author,
        'timestamp': timestamp,
        'plugin_origin': pluginOrigin,
        'feedback': feedback,
      };
}

class EditRecord {
  final String timestamp;
  final String author;
  final String reason;

  EditRecord({
    required this.timestamp,
    required this.author,
    required this.reason,
  });

  factory EditRecord.fromJson(Map<String, dynamic> json) {
    return EditRecord(
      timestamp: json['timestamp'] as String,
      author: json['author'] as String,
      reason: json['reason'] as String,
    );
  }
}

class JournalEntry {
  final String id;
  final List<int> encrypted;
  final List<int> nonce;
  final List<int> salt;
  final Provenance provenance;
  final String kind;
  final List<String> tags;
  final String displayTitle;
  final bool pinned;
  final String? mood;
  final String? priority;
  final String? status;
  final String? dueDate;
  final String? parentProjectId;
  final List<EditRecord> history;

  JournalEntry({
    required this.id,
    required this.encrypted,
    required this.nonce,
    required this.salt,
    required this.provenance,
    this.kind = 'journal',
    this.tags = const [],
    this.displayTitle = '',
    this.pinned = false,
    this.mood,
    this.priority,
    this.status,
    this.dueDate,
    this.parentProjectId,
    this.history = const [],
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    List<int> parseBytes(dynamic v) {
      if (v is List) return v.map((e) => e as int).toList();
      if (v is String) {
        try {
          return base64Decode(v).toList();
        } catch (_) {
          try {
            final decoded = jsonDecode(v) as List<dynamic>;
            return decoded.map((e) => e as int).toList();
          } catch (e) {
            rethrow;
          }
        }
      }
      throw FormatException('Unsupported byte representation: ${v.runtimeType}');
    }

    return JournalEntry(
      id: json['id'] as String,
      encrypted: parseBytes(json['encrypted']),
      nonce: parseBytes(json['nonce']),
      salt: parseBytes(json['salt']),
      provenance: Provenance.fromJson(json['provenance'] as Map<String, dynamic>),
      kind: (json['kind'] as String?) ?? 'journal',
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      displayTitle: (json['display_title'] as String?) ?? '',
      pinned: (json['pinned'] as bool?) ?? false,
      mood: json['mood'] as String?,
      priority: json['priority'] as String?,
      status: json['status'] as String?,
      dueDate: json['due_date'] as String?,
      parentProjectId: json['parent_project_id'] as String?,
      history: (json['history'] as List<dynamic>?)
              ?.map((e) => EditRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  String get author => provenance.author;
  String get timestamp => provenance.timestamp;

  String decryptText(String password, LumenCore lumen) {
    return lumen.decryptEntry(id, password);
  }
}
