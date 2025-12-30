import 'dart:convert';

import '../lumen_core.dart';

class Provenance {
  final String author;
  final String timestamp;

  Provenance({
    required this.author,
    required this.timestamp,
  });

  factory Provenance.fromJson(Map<String, dynamic> json) {
    return Provenance(
      author: json['author'] as String,
      timestamp: json['timestamp'] as String,
    );
  }
}

class JournalEntry {
  final String id;
  final List<int> encrypted;
  final List<int> nonce;
  final List<int> salt;
  final Provenance provenance;

  JournalEntry({
    required this.id,
    required this.encrypted,
    required this.nonce,
    required this.salt,
    required this.provenance,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    List<int> parseBytes(dynamic v) {
      if (v is List) return v.map((e) => e as int).toList();
      if (v is String) {
        // Could be a base64 string or a JSON-encoded array string
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
    );
  }

  String get author => provenance.author;
  String get timestamp => provenance.timestamp;

  String decryptText(String password, LumenCore lumen) {
    return lumen.decryptEntry(id, password);
  }
}
