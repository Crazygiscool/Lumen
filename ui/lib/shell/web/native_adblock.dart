/// Native ad blocker for the WPE-backed federated webview.
///
/// Translates the WebKit content-rule JSON `parts` (already produced by
/// `libublock`) into the compact binary blob consumed by the vendored
/// `webview_flutter_linux` native extension, which matches subresource
/// requests in the web process before dispatch. The blob is versioned in its
/// header so the extension reloads it only when the rule-set revision changes.
library;

import 'dart:convert';
import 'dart:typed_data';

/// WebKit content-rule resource-type strings → native bit constants.
///
/// Kept in sync with `rust/src/wpe_runtime/adblock.rs`. A rule with no
/// `resource-type` carries mask `0`, meaning "matches every request type".
const int typeDocument = 1 << 0; // ignores: native document blocking off
const int typeImage = 1 << 1;
const int typeStyleSheet = 1 << 2;
const int typeScript = 1 << 3;
const int typeFont = 1 << 4;
const int typeRaw = 1 << 5;
const int typeSvgDocument = 1 << 6;
const int typeMedia = 1 << 7;
const int typePing = 1 << 8;
const int typeFetch = 1 << 9;
const int typeWebsocket = 1 << 10;
const int typePopup = 1 << 11;
const int typeOther = 1 << 12;

int _typeBit(String name) {
  switch (name) {
    case 'document':
      return typeDocument;
    case 'image':
      return typeImage;
    case 'style-sheet':
      return typeStyleSheet;
    case 'script':
      return typeScript;
    case 'font':
      return typeFont;
    case 'svg-document':
      return typeSvgDocument;
    case 'media':
      return typeMedia;
    case 'raw':
      return typeRaw;
    case 'ping':
      return typePing;
    case 'fetch':
      return typeFetch;
    case 'websocket':
      return typeWebsocket;
    case 'popup':
      return typePopup;
    default:
      return typeOther;
  }
}

/// Compiles [parts] (content-rule JSON documents) into the binary rule blob.
///
/// [version] identifies the rule-set revision; the web-process extension loads
/// a blob only when its version differs from the installed table.
Uint8List buildContentRuleBlob(List<String> parts, {required int version}) {
  final blocks = <_NativeRule>[];
  final exceptions = <_NativeRule>[];

  for (final part in parts) {
    List<dynamic> rules;
    try {
      rules = (jsonDecode(part) as List).cast<dynamic>();
    } catch (_) {
      continue;
    }
    for (final raw in rules) {
      if (raw is! Map) continue;
      final trigger = (raw['trigger'] as Map?)?.cast<String, dynamic>();
      final action = (raw['action'] as Map?)?.cast<String, dynamic>();
      if (trigger == null || action == null) continue;

      final urlFilter = trigger['url-filter'] as String? ?? '';
      if (urlFilter.isEmpty) continue;

      final types = _typeMask(trigger['resource-type']);
      final ifDomain = _stringList(trigger['if-domain']);
      final unlessDomain = _stringList(trigger['unless-domain']);

      switch (action['type'] as String? ?? '') {
        case 'block':
          blocks.add(_NativeRule(urlFilter, types, ifDomain, unlessDomain));
          break;
        case 'ignore-previous-rules':
          exceptions.add(_NativeRule(urlFilter, types, ifDomain, unlessDomain));
          break;
      }
    }
  }

  final writer = _BlobWriter()
    ..raw('LUNALB1\u0000'.codeUnits)
    ..u64(version)
    ..u64(blocks.length)
    ..u64(exceptions.length);
  for (final rule in blocks) {
    rule.writeTo(writer);
  }
  for (final rule in exceptions) {
    rule.writeTo(writer);
  }
  return writer.bytes;
}

final class _NativeRule {
  const _NativeRule(this.urlFilter, this.types, this.ifDomain, this.unlessDomain);

  final String urlFilter;
  final int types;
  final List<String> ifDomain;
  final List<String> unlessDomain;

  void writeTo(_BlobWriter writer) {
    final regex = utf8.encode(urlFilter);
    writer.u32(regex.length).raw(regex);
    writer.u32(types);
    _writeDomains(writer, ifDomain);
    _writeDomains(writer, unlessDomain);
  }

  void _writeDomains(_BlobWriter writer, List<String> domains) {
    writer.u32(domains.length);
    for (final domain in domains) {
      final bytes = utf8.encode(domain);
      writer.u32(bytes.length).raw(bytes);
    }
  }
}

final class _BlobWriter {
  final BytesBuilder _builder = BytesBuilder(copy: true);
  final ByteData _scratch = ByteData(8);

  _BlobWriter u64(int value) {
    _scratch.setUint64(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 8));
    return this;
  }

  _BlobWriter u32(int value) {
    _scratch.setUint32(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4));
    return this;
  }

  _BlobWriter raw(List<int> values) {
    _builder.add(values);
    return this;
  }

  Uint8List get bytes => _builder.toBytes();
}

int _typeMask(Object? value) {
  final list = _stringList(value);
  if (list.isEmpty) return 0;
  var mask = 0;
  for (final name in list) {
    mask |= _typeBit(name);
  }
  return mask;
}

List<String> _stringList(Object? v) {
  if (v == null) return const [];
  if (v is List) {
    return [for (final e in v) e as String? ?? ''];
  }
  if (v is String) return [v];
  return const [];
}