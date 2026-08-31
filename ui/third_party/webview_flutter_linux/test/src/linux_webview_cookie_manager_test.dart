// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart';

void main() {
  group('LinuxCookieAcceptPolicy', () {
    test('matches every public WebKit cookie policy value', () {
      expect(LinuxCookieAcceptPolicy.always.nativeValue, 0);
      expect(LinuxCookieAcceptPolicy.never.nativeValue, 1);
      expect(LinuxCookieAcceptPolicy.noThirdParty.nativeValue, 2);
    });

    test('decodes every public WebKit cookie policy value', () {
      expect(
        LinuxCookieAcceptPolicy.fromNativeValue(0),
        LinuxCookieAcceptPolicy.always,
      );
      expect(
        LinuxCookieAcceptPolicy.fromNativeValue(1),
        LinuxCookieAcceptPolicy.never,
      );
      expect(
        LinuxCookieAcceptPolicy.fromNativeValue(2),
        LinuxCookieAcceptPolicy.noThirdParty,
      );
    });

    test('rejects unknown native policy values', () {
      expect(
        () => LinuxCookieAcceptPolicy.fromNativeValue(3),
        throwsStateError,
      );
    });
  });
}
