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
  final String encrypted;
  final String nonce;
  final String salt;
  final Provenance provenance;

  JournalEntry({
    required this.id,
    required this.encrypted,
    required this.nonce,
    required this.salt,
    required this.provenance,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    return JournalEntry(
      id: json['id'] as String,
      encrypted: json['encrypted'] as String,
      nonce: json['nonce'] as String,
      salt: json['salt'] as String,
      provenance:
          Provenance.fromJson(json['provenance'] as Map<String, dynamic>),
    );
  }

  String get author => provenance.author;
  String get timestamp => provenance.timestamp;

  String decryptText(String password, LumenCore lumen) {
    return lumen.decryptEntry(id, password);
  }
}
