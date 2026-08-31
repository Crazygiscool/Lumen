// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/src/webview_attachment_lease.dart';

void main() {
  group('WebViewAttachmentLease', () {
    test('permits idempotent ownership and a later replacement', () {
      final lease = WebViewAttachmentLease();
      final first = Object();
      final second = Object();

      expect(lease.isAttached, isFalse);
      lease.acquire(first);
      lease.acquire(first);
      expect(lease.isAttached, isTrue);
      expect(lease.release(first), isTrue);
      expect(lease.isAttached, isFalse);

      lease.acquire(second);
      expect(lease.isAttached, isTrue);
    });

    test('rejects concurrent owners and ignores stale releases', () {
      final lease = WebViewAttachmentLease();
      final current = Object();
      final stale = Object();

      lease.acquire(current);

      expect(() => lease.acquire(stale), throwsStateError);
      expect(lease.release(stale), isFalse);
      expect(lease.isAttached, isTrue);
      expect(lease.release(current), isTrue);
    });

    test('clear releases an owner during explicit disposal', () {
      final lease = WebViewAttachmentLease()..acquire(Object());

      lease.clear();

      expect(lease.isAttached, isFalse);
    });
  });
}
