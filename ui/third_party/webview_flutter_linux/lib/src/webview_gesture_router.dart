// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Routes pointer sequences to a texture-backed WebView through Flutter's
/// gesture arena.
///
/// A native platform view normally gets this behavior from Flutter's render
/// objects. The Linux WebView is a [Texture], however, so it must reproduce the
/// same contract itself: cache a sequence while recognizers compete, forward
/// it if the WebView's arena team wins, and discard it if an ancestor wins.
///
/// This implementation follows Flutter's private platform-view gesture router
/// and additionally admits [PointerPanZoomStartEvent] streams. Trackpad input
/// therefore follows the same ownership decision as touch and mouse input.
final class WebViewGestureRouter extends OneSequenceGestureRecognizer {
  /// Creates a router for the recognizer factories supplied to
  /// `PlatformWebViewWidgetCreationParams`.
  WebViewGestureRouter(
    this._handlePointerEvent,
    this.gestureRecognizerFactories,
  ) {
    assert(
      _factoryTypes(gestureRecognizerFactories).length ==
          gestureRecognizerFactories.length,
      'There must be only one WebView gesture recognizer factory per type.',
    );
    team = GestureArenaTeam()..captain = this;
    _gestureRecognizers = gestureRecognizerFactories.map((factory) {
      final recognizer = factory.constructor();
      recognizer.team = team;

      // These recognizers stay out of the arena when they have no callback.
      // Placeholder callbacks let the factory express gesture ownership
      // without requiring the application to install an unrelated handler.
      switch (recognizer) {
        case LongPressGestureRecognizer():
          recognizer.onLongPress ??= () {};
        case DragGestureRecognizer():
          recognizer.onDown ??= (_) {};
        case TapGestureRecognizer():
          recognizer.onTapDown ??= (_) {};
      }
      return recognizer;
    }).toSet();
  }

  final void Function(PointerEvent event) _handlePointerEvent;

  /// Factories whose recognized gestures should belong to the WebView.
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizerFactories;

  late final Set<OneSequenceGestureRecognizer> _gestureRecognizers;
  final Map<int, List<PointerEvent>> _cachedEvents =
      <int, List<PointerEvent>>{};
  final Set<int> _forwardedPointers = <int>{};

  /// Whether two factory sets create the same recognizer types.
  ///
  /// Platform-view updates compare types rather than closure identity because
  /// applications commonly rebuild equivalent [Factory] instances.
  static bool hasSameFactoryTypes(
    Set<Factory<OneSequenceGestureRecognizer>> first,
    Set<Factory<OneSequenceGestureRecognizer>> second,
  ) => setEquals(_factoryTypes(first), _factoryTypes(second));

  static Set<Type> _factoryTypes(
    Set<Factory<OneSequenceGestureRecognizer>> factories,
  ) => factories.map((factory) => factory.type).toSet();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    for (final recognizer in _gestureRecognizers) {
      recognizer.addPointer(event);
    }
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    for (final recognizer in _gestureRecognizers) {
      recognizer.addPointerPanZoom(event);
    }
  }

  @override
  String get debugDescription => 'Linux WebView';

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void handleEvent(PointerEvent event) {
    if (_forwardedPointers.contains(event.pointer)) {
      _handlePointerEvent(event);
    } else {
      (_cachedEvents[event.pointer] ??= <PointerEvent>[]).add(event);
    }
    stopTrackingIfPointerNoLongerDown(event);
  }

  @override
  void acceptGesture(int pointer) {
    final events = _cachedEvents.remove(pointer);
    if (events != null) {
      for (final event in events) {
        _handlePointerEvent(event);
      }
    }
    _forwardedPointers.add(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
    _cachedEvents.remove(pointer);
  }

  @override
  void stopTrackingPointer(int pointer) {
    super.stopTrackingPointer(pointer);
    _forwardedPointers.remove(pointer);
  }

  /// Rejects all unresolved sequences before this router leaves the tree.
  void reset() {
    for (final pointer in _forwardedPointers.toList()) {
      super.stopTrackingPointer(pointer);
    }
    _forwardedPointers.clear();
    for (final pointer in _cachedEvents.keys.toList()) {
      super.stopTrackingPointer(pointer);
    }
    _cachedEvents.clear();
    resolve(GestureDisposition.rejected);
  }

  @override
  void dispose() {
    for (final recognizer in _gestureRecognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }
}
