// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';

/// Claims a mouse-wheel event for the deepest WebView under the pointer.
///
/// Pointer signals do not enter the ordinary gesture arena. Registering with
/// Flutter's signal resolver prevents an ancestor [Scrollable] from consuming
/// the same wheel event after the WebView has handled it.
bool registerWebViewPointerScroll(
  PointerSignalEvent event,
  void Function(PointerScrollEvent event) onResolved,
) {
  if (event is! PointerScrollEvent) return false;
  GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
    if (resolved is PointerScrollEvent) onResolved(resolved);
  });
  return true;
}

/// Converts Flutter mouse-wheel deltas to WPE scroll deltas.
///
/// Flutter's Linux embedder expands each GDK wheel tick by 53 logical pixels.
/// WPE accepts discrete mouse-wheel ticks and applies its own line-step size,
/// with the opposite sign convention. Undoing Flutter's expansion avoids
/// applying WPE's precise-delta multiplier to an already expanded wheel step.
Offset wpeMouseWheelDelta(Offset flutterDelta) => -flutterDelta / 53;

/// Converts a Flutter trackpad pan delta to a WPE scroll delta.
///
/// Flutter's Linux embedder expands GDK touchpad deltas by 53 before exposing
/// them as pan/zoom events. WPE expects the original precise axis delta, so the
/// bridge removes that expansion without changing the finger-movement sign.
/// Keeping the result as a double preserves sub-pixel trackpad motion.
Offset wpeTrackpadPanDelta(Offset flutterDelta) => flutterDelta / 53;

/// Browser-history operation represented by a dedicated desktop mouse button.
enum WpeMouseHistoryAction {
  /// Navigate to the previous back-forward-list item.
  back,

  /// Navigate to the next back-forward-list item.
  forward,
}

/// Decodes newly pressed Flutter mouse-button bits into browser history work.
///
/// Primary, middle, secondary, and unknown buttons remain ordinary page input.
/// A mouse can report both side buttons in one transition, so the result keeps
/// the stable back-then-forward ordering instead of collapsing to one action.
List<WpeMouseHistoryAction> wpeMouseHistoryActions(int changedButtons) => [
  if (changedButtons & kBackMouseButton != 0) WpeMouseHistoryAction.back,
  if (changedButtons & kForwardMouseButton != 0) WpeMouseHistoryAction.forward,
];

/// Preserves sub-pixel scrolling while adapting Flutter doubles to WPE ints.
///
/// Trackpads commonly deliver deltas smaller than one logical pixel. Rounding
/// each event independently would either discard those events or exaggerate
/// them. This accumulator carries the fractional remainder into later events.
final class WpeScrollAccumulator {
  Offset _remainder = Offset.zero;

  /// Adds [delta] and returns the whole-pixel portion ready for WPE.
  (int, int) add(Offset delta) {
    final total = _remainder + delta;
    final deltaX = total.dx.truncate();
    final deltaY = total.dy.truncate();
    _remainder = Offset(total.dx - deltaX, total.dy - deltaY);
    return (deltaX, deltaY);
  }

  /// Drops any remainder when a gesture stream finishes or is cancelled.
  void reset() => _remainder = Offset.zero;
}

/// Direction selected by a completed horizontal history swipe.
enum WpeNavigationSwipeDirection {
  /// A rightward finger motion requests the previous history item.
  back,

  /// A leftward finger motion requests the next history item.
  forward,
}

/// Classification of one update in a possible history-navigation swipe.
final class WpeNavigationSwipeUpdate {
  const WpeNavigationSwipeUpdate({
    required this.claimsGesture,
    required this.progress,
    this.direction,
  });

  /// Whether navigation owns the pan instead of forwarding it to page scroll.
  final bool claimsGesture;

  /// Normalized distance toward the navigation threshold, from zero to one.
  final double progress;

  /// Current history direction, or null before horizontal intent is known.
  final WpeNavigationSwipeDirection? direction;
}

enum _WpeSwipeAxis { undecided, horizontal, vertical }

/// Distinguishes an opt-in history swipe from ordinary touchpad scrolling.
///
/// WPE's GTK port has a native view gesture controller, but the headless WPE
/// view deliberately has no window-system gesture surface. Flutter therefore
/// classifies the original unscaled pan deltas before forwarding them to WPE.
/// Vertical intent always remains page scroll. Horizontal intent is claimed
/// only when history exists in that direction, so a page can still scroll
/// horizontally at the beginning or end of its browser history.
final class WpeNavigationSwipeTracker {
  WpeNavigationSwipeTracker({
    this.axisSlop = 12,
    this.axisDominance = 1.35,
    this.triggerFraction = 0.18,
    this.minimumTriggerDistance = 96,
    this.maximumTriggerDistance = 240,
  }) : assert(axisSlop >= 0),
       assert(axisDominance >= 1),
       assert(triggerFraction > 0),
       assert(minimumTriggerDistance > 0),
       assert(maximumTriggerDistance >= minimumTriggerDistance);

  /// Movement required before horizontal or vertical intent is classified.
  final double axisSlop;

  /// Required ratio between the dominant and secondary axes.
  final double axisDominance;

  /// Fraction of viewport width required to commit navigation.
  final double triggerFraction;

  /// Lower bound for the commit distance on narrow views.
  final double minimumTriggerDistance;

  /// Upper bound for the commit distance on wide views.
  final double maximumTriggerDistance;

  bool _enabled = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  double _triggerDistance = 0;
  Offset _pan = Offset.zero;
  _WpeSwipeAxis _axis = _WpeSwipeAxis.undecided;

  /// Starts a new touchpad stream using a point-in-time history snapshot.
  void start({
    required bool enabled,
    required bool canGoBack,
    required bool canGoForward,
    required double viewportWidth,
  }) {
    _enabled = enabled;
    _canGoBack = canGoBack;
    _canGoForward = canGoForward;
    _triggerDistance = (viewportWidth * triggerFraction)
        .clamp(minimumTriggerDistance, maximumTriggerDistance)
        .toDouble();
    _pan = Offset.zero;
    _axis = _WpeSwipeAxis.undecided;
  }

  /// Adds one unscaled Flutter pan delta and returns its current classification.
  WpeNavigationSwipeUpdate add(Offset delta) {
    if (!_enabled) return _passthrough;
    _pan += delta;
    final horizontal = _pan.dx.abs();
    final vertical = _pan.dy.abs();

    if (_axis == _WpeSwipeAxis.undecided) {
      if (horizontal >= axisSlop && horizontal >= vertical * axisDominance) {
        _axis = _WpeSwipeAxis.horizontal;
      } else if (vertical >= axisSlop &&
          vertical >= horizontal * axisDominance) {
        _axis = _WpeSwipeAxis.vertical;
      }
    }
    if (_axis != _WpeSwipeAxis.horizontal || _pan.dx == 0) {
      return _passthrough;
    }

    final direction = _pan.dx > 0
        ? WpeNavigationSwipeDirection.back
        : WpeNavigationSwipeDirection.forward;
    final available = switch (direction) {
      WpeNavigationSwipeDirection.back => _canGoBack,
      WpeNavigationSwipeDirection.forward => _canGoForward,
    };
    if (!available) return _passthrough;
    return WpeNavigationSwipeUpdate(
      claimsGesture: true,
      progress: (horizontal / _triggerDistance).clamp(0, 1),
      direction: direction,
    );
  }

  /// Completes the stream and returns a direction only past the threshold.
  WpeNavigationSwipeDirection? end() {
    final update = add(Offset.zero);
    final direction = update.claimsGesture && update.progress >= 1
        ? update.direction
        : null;
    cancel();
    return direction;
  }

  /// Forgets classification and distance after cancellation or pinch takeover.
  void cancel() {
    _enabled = false;
    _canGoBack = false;
    _canGoForward = false;
    _triggerDistance = 0;
    _pan = Offset.zero;
    _axis = _WpeSwipeAxis.undecided;
  }

  static const WpeNavigationSwipeUpdate _passthrough = WpeNavigationSwipeUpdate(
    claimsGesture: false,
    progress: 0,
  );
}

/// Counts consecutive desktop pointer presses for WebKit.
///
/// WPE expects an explicit press count on pointer-down events. Flutter exposes
/// raw button transitions, so the texture surface must recognize a nearby
/// second or third press itself. Counts wrap after three because WPE accepts
/// only single, double, and triple clicks.
final class WpeClickCounter {
  WpeClickCounter({
    this.timeout = const Duration(milliseconds: 500),
    this.slop = 5,
  }) : assert(!timeout.isNegative),
       assert(slop >= 0);

  /// Longest interval that can continue the current multi-click sequence.
  final Duration timeout;

  /// Maximum logical-pixel movement between consecutive presses.
  final double slop;

  int? _button;
  Duration? _timeStamp;
  Offset? _position;
  int _count = 0;

  /// Records a button-down transition and returns its WPE press count.
  int register({
    required int button,
    required Duration timeStamp,
    required Offset position,
  }) {
    final previousTimeStamp = _timeStamp;
    final previousPosition = _position;
    final elapsed = previousTimeStamp == null
        ? null
        : timeStamp - previousTimeStamp;
    final continuesSequence =
        _button == button &&
        elapsed != null &&
        !elapsed.isNegative &&
        elapsed <= timeout &&
        previousPosition != null &&
        (position - previousPosition).distanceSquared <= slop * slop;

    _count = continuesSequence && _count < 3 ? _count + 1 : 1;
    _button = button;
    _timeStamp = timeStamp;
    _position = position;
    return _count;
  }

  /// Forgets an unfinished sequence when the pointer stream is cancelled.
  void reset() {
    _button = null;
    _timeStamp = null;
    _position = null;
    _count = 0;
  }
}
