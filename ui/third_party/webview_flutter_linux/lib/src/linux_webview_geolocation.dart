// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'native_frame_bindings.dart';

/// One position supplied by an application-owned Linux location provider.
///
/// Latitude, longitude, and horizontal accuracy are required by WPE. Optional
/// fields are forwarded only when non-null, preserving the distinction between
/// an unavailable measurement and a measured value of zero.
final class LinuxWebViewGeolocationPosition {
  /// Creates an immutable W3C-compatible position snapshot.
  const LinuxWebViewGeolocationPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.timestamp,
    this.altitude,
    this.altitudeAccuracy,
    this.heading,
    this.speed,
  });

  /// Latitude in degrees, from -90 through 90.
  final double latitude;

  /// Longitude in degrees, from -180 through 180.
  final double longitude;

  /// Horizontal accuracy radius in meters.
  final double accuracy;

  /// Time at which this position was measured, or native current time.
  final DateTime? timestamp;

  /// Altitude above sea level in meters.
  final double? altitude;

  /// Altitude accuracy in meters.
  final double? altitudeAccuracy;

  /// Clockwise direction of travel in degrees from true north.
  final double? heading;

  /// Ground speed in meters per second.
  final double? speed;
}

/// Current demand from WPE's application-global geolocation manager.
final class LinuxWebViewGeolocationState {
  /// Creates one immutable manager state transition.
  const LinuxWebViewGeolocationState({
    required this.active,
    required this.highAccuracy,
  });

  /// Whether at least one permitted page currently needs position updates.
  final bool active;

  /// Whether active pages requested high-accuracy positions.
  final bool highAccuracy;
}

/// Receives WPE geolocation start, stop, and accuracy transitions.
typedef LinuxWebViewGeolocationChangedCallback =
    FutureOr<void> Function(LinuxWebViewGeolocationState state);

/// Application-global geolocation provider for headless WPE WebKit.
///
/// Without a callback, WPE's `start` signal remains unclaimed and WebKit may
/// use GeoClue when it is installed. Registering a callback claims subsequent
/// requests: the application must then call [updatePosition] whenever its
/// location source changes, or [reportError] when no position can be obtained.
/// A stopped state tells the application it may release its location source.
final class LinuxWebViewGeolocationManager {
  LinuxWebViewGeolocationManager._({
    int Function(int enabled)? setProviderEnabled,
    int Function()? eventCount,
    int Function()? eventActive,
    int Function()? eventHighAccuracy,
    int Function()? eventPop,
    int Function(
      double latitude,
      double longitude,
      double accuracy,
      int timestampSeconds,
      int optionalMask,
      double altitude,
      double altitudeAccuracy,
      double heading,
      double speed,
    )?
    updatePosition,
    int Function(ffi.Pointer<ffi.Char> message)? fail,
    this.pollInterval = const Duration(milliseconds: 16),
  }) : _setProviderEnabled =
           setProviderEnabled ??
           webviewFlutterLinuxGeolocationSetProviderEnabled,
       _eventCount = eventCount ?? webviewFlutterLinuxGeolocationEventCount,
       _eventActive = eventActive ?? webviewFlutterLinuxGeolocationEventActive,
       _eventHighAccuracy =
           eventHighAccuracy ?? webviewFlutterLinuxGeolocationEventHighAccuracy,
       _eventPop = eventPop ?? webviewFlutterLinuxGeolocationEventPop,
       _updatePosition =
           updatePosition ?? webviewFlutterLinuxGeolocationUpdatePosition,
       _fail = fail ?? webviewFlutterLinuxGeolocationFailed;

  /// Creates an injectable manager for unit tests.
  @visibleForTesting
  factory LinuxWebViewGeolocationManager.forTesting({
    required int Function(int enabled) setProviderEnabled,
    required int Function() eventCount,
    required int Function() eventActive,
    required int Function() eventHighAccuracy,
    required int Function() eventPop,
    required int Function(
      double latitude,
      double longitude,
      double accuracy,
      int timestampSeconds,
      int optionalMask,
      double altitude,
      double altitudeAccuracy,
      double heading,
      double speed,
    )
    updatePosition,
    required int Function(ffi.Pointer<ffi.Char> message) fail,
    Duration pollInterval = const Duration(days: 1),
  }) => LinuxWebViewGeolocationManager._(
    setProviderEnabled: setProviderEnabled,
    eventCount: eventCount,
    eventActive: eventActive,
    eventHighAccuracy: eventHighAccuracy,
    eventPop: eventPop,
    updatePosition: updatePosition,
    fail: fail,
    pollInterval: pollInterval,
  );

  /// Shared provider used by every WPE WebView in this process.
  static final LinuxWebViewGeolocationManager instance =
      LinuxWebViewGeolocationManager._();

  static const int _altitudeFlag = 1 << 0;
  static const int _altitudeAccuracyFlag = 1 << 1;
  static const int _headingFlag = 1 << 2;
  static const int _speedFlag = 1 << 3;

  final int Function(int enabled) _setProviderEnabled;
  final int Function() _eventCount;
  final int Function() _eventActive;
  final int Function() _eventHighAccuracy;
  final int Function() _eventPop;
  final int Function(
    double latitude,
    double longitude,
    double accuracy,
    int timestampSeconds,
    int optionalMask,
    double altitude,
    double altitudeAccuracy,
    double heading,
    double speed,
  )
  _updatePosition;
  final int Function(ffi.Pointer<ffi.Char> message) _fail;

  /// Polling cadence used only while an application provider is registered.
  @visibleForTesting
  final Duration pollInterval;

  LinuxWebViewGeolocationChangedCallback? _onChanged;
  Timer? _pollTimer;

  /// Claims WPE location requests, or restores the native GeoClue fallback.
  Future<void> setOnGeolocationChanged(
    LinuxWebViewGeolocationChangedCallback? onChanged,
  ) async {
    final previous = _onChanged;
    _onChanged = onChanged;
    final status = _setProviderEnabled(onChanged == null ? 0 : 1);
    if (status != 0) {
      _onChanged = previous;
      throw StateError(
        'Native geolocation provider update failed with status $status.',
      );
    }
    if (onChanged == null) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _discardEvents();
      return;
    }
    _pollTimer ??= Timer.periodic(pollInterval, (_) => _drainEvents());
    scheduleMicrotask(_drainEvents);
  }

  /// Publishes a position while WPE has an active claimed request.
  Future<void> updatePosition(LinuxWebViewGeolocationPosition position) async {
    _validatePosition(position);
    var optionalMask = 0;
    if (position.altitude != null) optionalMask |= _altitudeFlag;
    if (position.altitudeAccuracy != null) {
      optionalMask |= _altitudeAccuracyFlag;
    }
    if (position.heading != null) optionalMask |= _headingFlag;
    if (position.speed != null) optionalMask |= _speedFlag;
    final timestampSeconds = position.timestamp == null
        ? 0
        : position.timestamp!.millisecondsSinceEpoch ~/ 1000;
    final status = _updatePosition(
      position.latitude,
      position.longitude,
      position.accuracy,
      timestampSeconds,
      optionalMask,
      position.altitude ?? 0,
      position.altitudeAccuracy ?? 0,
      position.heading ?? 0,
      position.speed ?? 0,
    );
    if (status != 0) {
      throw StateError(
        'Native geolocation position update failed with status $status.',
      );
    }
  }

  /// Reports a provider failure while WPE has an active claimed request.
  Future<void> reportError(String message) async {
    if (message.isEmpty) {
      throw ArgumentError.value(message, 'message', 'Must not be empty.');
    }
    final nativeMessage = message.toNativeUtf8();
    try {
      final status = _fail(nativeMessage.cast());
      if (status != 0) {
        throw StateError(
          'Native geolocation failure update failed with status $status.',
        );
      }
    } finally {
      calloc.free(nativeMessage);
    }
  }

  void _validatePosition(LinuxWebViewGeolocationPosition position) {
    void finiteRange(
      double value,
      String name,
      double minimum,
      double maximum,
    ) {
      if (!value.isFinite || value < minimum || value > maximum) {
        throw ArgumentError.value(
          value,
          name,
          'Must be finite and between $minimum and $maximum.',
        );
      }
    }

    finiteRange(position.latitude, 'latitude', -90, 90);
    finiteRange(position.longitude, 'longitude', -180, 180);
    if (!position.accuracy.isFinite || position.accuracy < 0) {
      throw ArgumentError.value(
        position.accuracy,
        'accuracy',
        'Must be finite and non-negative.',
      );
    }
    final timestamp = position.timestamp;
    if (timestamp != null && timestamp.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(
        timestamp,
        'timestamp',
        'Must not precede the Unix epoch.',
      );
    }
    if (position.altitude case final altitude? when !altitude.isFinite) {
      throw ArgumentError.value(altitude, 'altitude', 'Must be finite.');
    }
    if (position.altitudeAccuracy case final accuracy?
        when !accuracy.isFinite || accuracy < 0) {
      throw ArgumentError.value(
        accuracy,
        'altitudeAccuracy',
        'Must be finite and non-negative.',
      );
    }
    if (position.heading case final heading?
        when !heading.isFinite || heading < 0 || heading >= 360) {
      throw ArgumentError.value(
        heading,
        'heading',
        'Must be finite and at least zero but less than 360.',
      );
    }
    if (position.speed case final speed? when !speed.isFinite || speed < 0) {
      throw ArgumentError.value(
        speed,
        'speed',
        'Must be finite and non-negative.',
      );
    }
  }

  @visibleForTesting
  void drainEventsForTesting() => _drainEvents();

  void _drainEvents() {
    while (_eventCount() > 0) {
      final active = _eventActive();
      final highAccuracy = _eventHighAccuracy();
      final popStatus = _eventPop();
      if (active < 0 || highAccuracy < 0 || popStatus != 0) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError(
              'Invalid native geolocation event: active=$active, '
              'highAccuracy=$highAccuracy, pop=$popStatus.',
            ),
            library: 'webview_flutter_linux',
          ),
        );
        continue;
      }
      final callback = _onChanged;
      if (callback == null) continue;
      final state = LinuxWebViewGeolocationState(
        active: active != 0,
        highAccuracy: highAccuracy != 0,
      );
      Future<void>.sync(() => callback(state)).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'webview_flutter_linux',
            context: ErrorDescription('while handling a WPE geolocation event'),
          ),
        );
      });
    }
  }

  void _discardEvents() {
    while (_eventCount() > 0) {
      if (_eventPop() != 0) break;
    }
  }
}
