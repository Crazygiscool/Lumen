// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/src/wpe_keyboard.dart';

void main() {
  test('maps DOM-compatible Windows key codes', () {
    expect(webViewWindowsKeyCode(LogicalKeyboardKey.keyA), 0x41);
    expect(webViewWindowsKeyCode(LogicalKeyboardKey.digit7), 0x37);
    expect(webViewWindowsKeyCode(LogicalKeyboardKey.enter), 0x0d);
    expect(webViewWindowsKeyCode(LogicalKeyboardKey.arrowLeft), 0x25);
  });

  test('combines WebView keyboard modifier flags', () {
    expect(
      webViewKeyboardModifiers(
        shift: true,
        control: true,
        alt: false,
        meta: false,
        capsLock: false,
        numLock: false,
      ),
      webViewEventFlagShiftDown | webViewEventFlagControlDown,
    );
  });
}
