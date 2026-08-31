// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/src/linux_webview_controller.dart';
import 'package:webview_flutter_linux/src/linux_webview_widget.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  testWidgets('applies the requested WebView layout direction', (tester) async {
    final widget = LinuxWebViewWidget(
      PlatformWebViewWidgetCreationParams(
        controller: LinuxWebViewController(
          const PlatformWebViewControllerCreationParams(),
        ),
        layoutDirection: TextDirection.rtl,
      ),
    );
    Directionality? built;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            built = widget.build(context) as Directionality;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(built?.textDirection, TextDirection.rtl);
  });
}
