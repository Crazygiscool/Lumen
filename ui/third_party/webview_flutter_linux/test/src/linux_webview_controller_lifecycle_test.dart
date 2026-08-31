// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/src/linux_webview_controller.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engineContextChannel = MethodChannel('dev.irondash.engine_context');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineContextChannel, null);
  });

  test(
    'native-required APIs share creation before any widget attachment',
    () async {
      final engineHandle = Completer<int>();
      var engineLookups = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(engineContextChannel, (call) {
            expect(call.method, 'getEngineHandle');
            engineLookups += 1;
            return engineHandle.future;
          });
      final controller = LinuxWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );

      final sideEffect = controller.runJavaScript('window.preAttach = true;');
      final result = controller.runJavaScriptReturningResult('6 * 7');
      final userAgent = controller.getUserAgent();
      final sideEffectExpectation = expectLater(
        sideEffect,
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'engine-probe',
          ),
        ),
      );
      final resultExpectation = expectLater(
        result,
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'engine-probe',
          ),
        ),
      );
      final userAgentExpectation = expectLater(
        userAgent,
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'engine-probe',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(engineLookups, 1);
      engineHandle.completeError(
        PlatformException(
          code: 'engine-probe',
          message: 'Stop before constructing a native texture in this test.',
        ),
      );

      await Future.wait(<Future<void>>[
        sideEffectExpectation,
        resultExpectation,
        userAgentExpectation,
      ]);
    },
  );
}
