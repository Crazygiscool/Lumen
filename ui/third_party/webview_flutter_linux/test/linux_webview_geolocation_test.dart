// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart';

void main() {
  test('claims lifecycle events and restores native fallback', () async {
    final events = <({int active, int highAccuracy})>[
      (active: 1, highAccuracy: 0),
      (active: 1, highAccuracy: 1),
      (active: 0, highAccuracy: 0),
    ];
    final enabledValues = <int>[];
    final states = <LinuxWebViewGeolocationState>[];
    final manager = _manager(
      events: events,
      setProviderEnabled: (enabled) {
        enabledValues.add(enabled);
        return 0;
      },
    );

    await manager.setOnGeolocationChanged(states.add);
    manager.drainEventsForTesting();
    await Future<void>.delayed(Duration.zero);

    expect(enabledValues, <int>[1]);
    expect(
      states.map((state) => (state.active, state.highAccuracy)),
      <(bool, bool)>[(true, false), (true, true), (false, false)],
    );
    expect(events, isEmpty);

    await manager.setOnGeolocationChanged(null);
    expect(enabledValues, <int>[1, 0]);
  });

  test('forwards every position field and its presence mask', () async {
    late final ({
      double latitude,
      double longitude,
      double accuracy,
      int timestampSeconds,
      int optionalMask,
      double altitude,
      double altitudeAccuracy,
      double heading,
      double speed,
    })
    update;
    final manager = _manager(
      updatePosition:
          (
            latitude,
            longitude,
            accuracy,
            timestampSeconds,
            optionalMask,
            altitude,
            altitudeAccuracy,
            heading,
            speed,
          ) {
            update = (
              latitude: latitude,
              longitude: longitude,
              accuracy: accuracy,
              timestampSeconds: timestampSeconds,
              optionalMask: optionalMask,
              altitude: altitude,
              altitudeAccuracy: altitudeAccuracy,
              heading: heading,
              speed: speed,
            );
            return 0;
          },
    );

    await manager.updatePosition(
      LinuxWebViewGeolocationPosition(
        latitude: 18.0179,
        longitude: -76.8099,
        accuracy: 12,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          1700000123000,
          isUtc: true,
        ),
        altitude: 14,
        altitudeAccuracy: 3,
        heading: 90,
        speed: 2.5,
      ),
    );

    expect(update.latitude, 18.0179);
    expect(update.longitude, -76.8099);
    expect(update.accuracy, 12);
    expect(update.timestampSeconds, 1700000123);
    expect(update.optionalMask, 15);
    expect(update.altitude, 14);
    expect(update.altitudeAccuracy, 3);
    expect(update.heading, 90);
    expect(update.speed, 2.5);
  });

  test('validates positions before entering native code', () async {
    var nativeCalls = 0;
    final manager = _manager(
      updatePosition: (_, _, _, _, _, _, _, _, _) {
        nativeCalls += 1;
        return 0;
      },
    );

    Future<void> rejects(LinuxWebViewGeolocationPosition position) async {
      await expectLater(manager.updatePosition(position), throwsArgumentError);
    }

    await rejects(
      const LinuxWebViewGeolocationPosition(
        latitude: 91,
        longitude: 0,
        accuracy: 1,
      ),
    );
    await rejects(
      const LinuxWebViewGeolocationPosition(
        latitude: 0,
        longitude: 0,
        accuracy: -1,
      ),
    );
    await rejects(
      const LinuxWebViewGeolocationPosition(
        latitude: 0,
        longitude: 0,
        accuracy: 1,
        heading: 360,
      ),
    );
    await rejects(
      LinuxWebViewGeolocationPosition(
        latitude: 0,
        longitude: 0,
        accuracy: 1,
        timestamp: DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true),
      ),
    );
    await expectLater(manager.reportError(''), throwsArgumentError);
    expect(nativeCalls, 0);
  });

  test('copies error text and exposes native failures', () async {
    String? reportedMessage;
    final manager = _manager(
      fail: (message) {
        reportedMessage = message.cast<Utf8>().toDartString();
        return 0;
      },
      updatePosition: (_, _, _, _, _, _, _, _, _) => -2,
    );

    await manager.reportError('Location source unavailable');
    expect(reportedMessage, 'Location source unavailable');
    await expectLater(
      manager.updatePosition(
        const LinuxWebViewGeolocationPosition(
          latitude: 18,
          longitude: -77,
          accuracy: 10,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

LinuxWebViewGeolocationManager _manager({
  List<({int active, int highAccuracy})>? events,
  int Function(int enabled)? setProviderEnabled,
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
}) {
  final queue = events ?? <({int active, int highAccuracy})>[];
  return LinuxWebViewGeolocationManager.forTesting(
    setProviderEnabled: setProviderEnabled ?? (_) => 0,
    eventCount: () => queue.length,
    eventActive: () => queue.isEmpty ? -1 : queue.first.active,
    eventHighAccuracy: () => queue.isEmpty ? -1 : queue.first.highAccuracy,
    eventPop: () {
      if (queue.isEmpty) return 1;
      queue.removeAt(0);
      return 0;
    },
    updatePosition: updatePosition ?? (_, _, _, _, _, _, _, _, _) => 0,
    fail: fail ?? (_) => 0,
  );
}
