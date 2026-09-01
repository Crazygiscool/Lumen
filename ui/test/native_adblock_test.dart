import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/shell/web/native_adblock.dart';

void main() {
  test('translates block and exception rules into a binary blob', () {
    final blob = buildContentRuleBlob([
      '[{"trigger":{"url-filter":"^https?://ads\\\\.example\\\\.com/.*"},"action":{"type":"block"}},'
          '{"trigger":{"url-filter":"^https?://ads\\\\.example\\\\.com/(front|home)/",'
          '"resource-type":["raw","fetch"]},"action":{"type":"block"}},'
          '{"trigger":{"url-filter":"^https?://ads\\\\.example\\\\.com/allowed/"},"action":{"type":"ignore-previous-rules"}}]',
    ], version: 7);

    final data = ByteData.sublistView(blob);
    expect(blob.sublist(0, 8).map(String.fromCharCode).join(), 'LUNALB1\u0000');
    expect(data.getUint64(8, Endian.little), 7);
    expect(data.getUint64(16, Endian.little), 2); // blocks
    expect(data.getUint64(24, Endian.little), 1); // exceptions

    // First rule: regex, types=0 (any), no domains.
    var offset = 32;
    final firstLen = data.getUint32(offset, Endian.little);
    offset += 4;
    offset += firstLen;
    expect(data.getUint32(offset, Endian.little), 0);
    offset += 4;
    expect(data.getUint32(offset, Endian.little), 0);
    offset += 4;
    expect(data.getUint32(offset, Endian.little), 0);
    offset += 4;

    // Second rule: raw|fetch mask, no domains.
    final secondLen = data.getUint32(offset, Endian.little);
    offset += 4;
    offset += secondLen;
    final mask = data.getUint32(offset, Endian.little);
    expect(mask & nativeAdblockRaw, isNonZero);
    expect(mask & nativeAdblockFetch, isNonZero);
    offset += 12;

    // Third rule (exception): no types, no domains.
    final thirdLen = data.getUint32(offset, Endian.little);
    offset += 4 + thirdLen;
    expect(data.getUint32(offset, Endian.little), 0);
    offset += 12;
    expect(offset, blob.length);
  });

  test('empty parts produce an empty table blob', () {
    final blob = buildContentRuleBlob(const [], version: 1);
    final data = ByteData.sublistView(blob);
    expect(data.getUint64(16, Endian.little), 0);
    expect(data.getUint64(24, Endian.little), 0);
    expect(blob.length, 32);
  });

  test('malformed parts are skipped, valid ones survive', () {
    final blob = buildContentRuleBlob([
      'not json',
      '[{"trigger":{"url-filter":"^https?://tracker\\\\.net/beacon\$","resource-type":["script"]},"action":{"type":"block"}}]',
      '{"trigger":{}}',
    ], version: 2);
    final data = ByteData.sublistView(blob);
    expect(data.getUint64(16, Endian.little), 1);
    final offset = 32;
    final regexLen = data.getUint32(offset, Endian.little);
    final mask = data.getUint32(offset + 4 + regexLen, Endian.little);
    expect(mask & nativeAdblockScript, isNonZero);
  });
}

// Convenience aliases mirroring the native constants in native_adblock.dart.
int get nativeAdblockRaw => typeRaw;
int get nativeAdblockFetch => typeFetch;
int get nativeAdblockScript => typeScript;