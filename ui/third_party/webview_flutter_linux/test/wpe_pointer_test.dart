// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/src/wpe_pointer.dart';

void main() {
  testWidgets('deepest WebView claims a nested mouse-wheel signal', (
    tester,
  ) async {
    var webViewEvents = 0;
    var ancestorEvents = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Listener(
          onPointerSignal: (event) {
            GestureBinding.instance.pointerSignalResolver.register(
              event,
              (_) => ancestorEvents += 1,
            );
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (event) {
              registerWebViewPointerScroll(event, (_) => webViewEvents += 1);
            },
            child: const SizedBox(width: 200, height: 200),
          ),
        ),
      ),
    );

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 100),
        scrollDelta: Offset(0, 53),
      ),
    );

    expect(webViewEvents, 1);
    expect(ancestorEvents, 0);
  });

  test('restores and inverts Flutter Linux mouse-wheel ticks for WPE', () {
    expect(wpeMouseWheelDelta(const Offset(53, -106)), const Offset(-1, 2));
  });

  test(
    'restores precise trackpad deltas without changing finger direction',
    () {
      expect(wpeTrackpadPanDelta(const Offset(53, -106)), const Offset(1, -2));
      expect(
        wpeTrackpadPanDelta(const Offset(0.53, -0.265)),
        const Offset(0.01, -0.005),
      );
    },
  );

  test('maps dedicated mouse side buttons to browser history actions', () {
    expect(wpeMouseHistoryActions(kPrimaryMouseButton), isEmpty);
    expect(wpeMouseHistoryActions(kBackMouseButton), <WpeMouseHistoryAction>[
      WpeMouseHistoryAction.back,
    ]);
    expect(wpeMouseHistoryActions(kForwardMouseButton), <WpeMouseHistoryAction>[
      WpeMouseHistoryAction.forward,
    ]);
    expect(
      wpeMouseHistoryActions(kBackMouseButton | kForwardMouseButton),
      <WpeMouseHistoryAction>[
        WpeMouseHistoryAction.back,
        WpeMouseHistoryAction.forward,
      ],
    );
  });

  test('accumulates fractional deltas instead of discarding them', () {
    final accumulator = WpeScrollAccumulator();

    expect(accumulator.add(const Offset(0.4, -0.4)), (0, 0));
    expect(accumulator.add(const Offset(0.4, -0.4)), (0, 0));
    expect(accumulator.add(const Offset(0.4, -0.4)), (1, -1));
    expect(accumulator.add(const Offset(0.8, -0.8)), (1, -1));
  });

  test('reset discards a previous gesture remainder', () {
    final accumulator = WpeScrollAccumulator()
      ..add(const Offset(0.75, -0.75))
      ..reset();

    expect(accumulator.add(const Offset(0.5, -0.5)), (0, 0));
  });

  test('commits available horizontal history swipes past the threshold', () {
    final tracker = WpeNavigationSwipeTracker()
      ..start(
        enabled: true,
        canGoBack: true,
        canGoForward: true,
        viewportWidth: 1000,
      );

    expect(
      tracker.add(const Offset(24, 2)),
      isA<WpeNavigationSwipeUpdate>()
          .having((update) => update.claimsGesture, 'claimsGesture', isTrue)
          .having(
            (update) => update.direction,
            'direction',
            WpeNavigationSwipeDirection.back,
          ),
    );
    tracker.add(const Offset(170, 0));
    expect(tracker.end(), WpeNavigationSwipeDirection.back);

    tracker.start(
      enabled: true,
      canGoBack: true,
      canGoForward: true,
      viewportWidth: 1000,
    );
    tracker.add(const Offset(-200, 4));
    expect(tracker.end(), WpeNavigationSwipeDirection.forward);
  });

  test('passes through vertical, disabled, and unavailable history pans', () {
    final tracker = WpeNavigationSwipeTracker();

    tracker.start(
      enabled: true,
      canGoBack: true,
      canGoForward: true,
      viewportWidth: 800,
    );
    expect(tracker.add(const Offset(10, 80)).claimsGesture, isFalse);
    expect(tracker.add(const Offset(200, 0)).claimsGesture, isFalse);
    expect(tracker.end(), isNull);

    tracker.start(
      enabled: false,
      canGoBack: true,
      canGoForward: true,
      viewportWidth: 800,
    );
    expect(tracker.add(const Offset(300, 0)).claimsGesture, isFalse);
    expect(tracker.end(), isNull);

    tracker.start(
      enabled: true,
      canGoBack: false,
      canGoForward: false,
      viewportWidth: 800,
    );
    expect(tracker.add(const Offset(300, 0)).claimsGesture, isFalse);
    expect(tracker.end(), isNull);
  });

  test('does not navigate when a claimed swipe stays below its threshold', () {
    final tracker = WpeNavigationSwipeTracker()
      ..start(
        enabled: true,
        canGoBack: true,
        canGoForward: false,
        viewportWidth: 1200,
      );

    final update = tracker.add(const Offset(120, 0));
    expect(update.claimsGesture, isTrue);
    expect(update.progress, lessThan(1));
    expect(tracker.end(), isNull);
  });

  test('counts nearby presses through a triple click then wraps', () {
    final counter = WpeClickCounter();

    expect(
      counter.register(
        button: 0,
        timeStamp: const Duration(milliseconds: 100),
        position: const Offset(20, 20),
      ),
      1,
    );
    expect(
      counter.register(
        button: 0,
        timeStamp: const Duration(milliseconds: 300),
        position: const Offset(22, 21),
      ),
      2,
    );
    expect(
      counter.register(
        button: 0,
        timeStamp: const Duration(milliseconds: 500),
        position: const Offset(21, 23),
      ),
      3,
    );
    expect(
      counter.register(
        button: 0,
        timeStamp: const Duration(milliseconds: 700),
        position: const Offset(20, 20),
      ),
      1,
    );
  });

  test('button, timeout, distance, and cancellation restart click count', () {
    final counter = WpeClickCounter();

    int register(int button, int milliseconds, Offset position) =>
        counter.register(
          button: button,
          timeStamp: Duration(milliseconds: milliseconds),
          position: position,
        );

    expect(register(0, 100, Offset.zero), 1);
    expect(register(1, 200, Offset.zero), 1);
    expect(register(1, 800, Offset.zero), 1);
    expect(register(1, 900, const Offset(6, 0)), 1);
    expect(register(1, 1000, const Offset(7, 0)), 2);
    counter.reset();
    expect(register(1, 1100, const Offset(7, 0)), 1);
  });
}
