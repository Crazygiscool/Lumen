// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/src/webview_gesture_router.dart';

void main() {
  testWidgets('forwards an unclaimed pointer sequence in order', (
    tester,
  ) async {
    final forwarded = <PointerEvent>[];
    final router = WebViewGestureRouter(forwarded.add, const {});
    addTearDown(router.dispose);
    await tester.pumpWidget(_gestureSurface(router: router));

    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveBy(const Offset(8, 4));
    await gesture.up();

    expect(forwarded, <Matcher>[
      isA<PointerDownEvent>(),
      isA<PointerMoveEvent>(),
      isA<PointerUpEvent>(),
    ]);
  });

  testWidgets('forwards dedicated mouse side-button sequences', (tester) async {
    final forwarded = <PointerEvent>[];
    final router = WebViewGestureRouter(forwarded.add, const {});
    addTearDown(router.dispose);
    await tester.pumpWidget(_gestureSurface(router: router));

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await gesture.down(const Offset(100, 100));
    await gesture.up();
    await tester.pump();

    expect(forwarded, <Matcher>[
      isA<PointerDownEvent>().having(
        (event) => event.buttons,
        'buttons',
        kBackMouseButton,
      ),
      isA<PointerUpEvent>(),
    ]);
  });

  testWidgets('discards a drag claimed by an ancestor', (tester) async {
    final forwarded = <PointerEvent>[];
    var ancestorDragStarts = 0;
    final router = WebViewGestureRouter(forwarded.add, const {});
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _gestureSurface(
        router: router,
        onAncestorVerticalDragStart: (_) => ancestorDragStarts += 1,
      ),
    );

    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.up();

    expect(ancestorDragStarts, 1);
    expect(forwarded, isEmpty);
  });

  testWidgets('claims configured gestures for the WebView arena team', (
    tester,
  ) async {
    final forwarded = <PointerEvent>[];
    var ancestorDragStarts = 0;
    final router = WebViewGestureRouter(forwarded.add, {
      Factory<VerticalDragGestureRecognizer>(VerticalDragGestureRecognizer.new),
    });
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _gestureSurface(
        router: router,
        onAncestorVerticalDragStart: (_) => ancestorDragStarts += 1,
      ),
    );

    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.up();

    expect(ancestorDragStarts, 0);
    expect(forwarded.first, isA<PointerDownEvent>());
    expect(forwarded, contains(isA<PointerMoveEvent>()));
    expect(forwarded.last, isA<PointerUpEvent>());
  });

  testWidgets('forwards a complete trackpad pan and zoom sequence', (
    tester,
  ) async {
    final forwarded = <PointerEvent>[];
    final router = WebViewGestureRouter(forwarded.add, const {});
    addTearDown(router.dispose);
    await tester.pumpWidget(_gestureSurface(router: router));

    final gesture = await tester.startGesture(
      const Offset(100, 100),
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomUpdate(
      const Offset(100, 100),
      pan: const Offset(6, 12),
      scale: 1.2,
    );
    await gesture.panZoomEnd();

    expect(forwarded, <Matcher>[
      isA<PointerPanZoomStartEvent>(),
      isA<PointerPanZoomUpdateEvent>(),
      isA<PointerPanZoomEndEvent>(),
    ]);
  });

  test('compares rebuilt factories by recognizer type', () {
    final first = <Factory<OneSequenceGestureRecognizer>>{
      Factory<VerticalDragGestureRecognizer>(VerticalDragGestureRecognizer.new),
    };
    final equivalent = <Factory<OneSequenceGestureRecognizer>>{
      Factory<VerticalDragGestureRecognizer>(VerticalDragGestureRecognizer.new),
    };
    final different = <Factory<OneSequenceGestureRecognizer>>{
      Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
    };

    expect(WebViewGestureRouter.hasSameFactoryTypes(first, equivalent), isTrue);
    expect(WebViewGestureRouter.hasSameFactoryTypes(first, different), isFalse);
  });
}

Widget _gestureSurface({
  required WebViewGestureRouter router,
  GestureDragStartCallback? onAncestorVerticalDragStart,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragStart: onAncestorVerticalDragStart,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: router.addPointer,
      onPointerPanZoomStart: router.addPointerPanZoom,
      child: const SizedBox(width: 200, height: 200),
    ),
  ),
);
