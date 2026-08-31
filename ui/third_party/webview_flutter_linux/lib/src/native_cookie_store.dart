// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'native_frame_bindings.dart';

/// An owned cookie copied from WPE's application-wide cookie store.
final class NativeCookie {
  /// Creates a cookie whose strings no longer borrow native memory.
  const NativeCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
  });

  /// Cookie name.
  final String name;

  /// Cookie value.
  final String value;

  /// Host or domain attribute.
  final String domain;

  /// Path attribute.
  final String path;
}

final class _NativeCookieResult {
  const _NativeCookieResult({
    required this.requestId,
    required this.status,
    required this.hadCookies,
    required this.acceptPolicy,
    required this.error,
    required this.cookies,
  });

  final int requestId;
  final int status;
  final bool? hadCookies;
  final int? acceptPolicy;
  final String error;
  final List<NativeCookie> cookies;
}

final class _PendingCookieOperation<T> {
  const _PendingCookieOperation({
    required this.completer,
    required this.decode,
  });

  final Completer<T> completer;
  final T Function(_NativeCookieResult result) decode;
}

/// Request-scoped Dart bridge for WPE's application-wide cookie manager.
///
/// WebKit completes cookie work asynchronously on GLib's platform thread. The
/// Rust callback copies each result into a FIFO queue, while a short-lived Dart
/// timer drains that queue only while operations are pending. Static request
/// state prevents separate `WebViewCookieManager` instances from reusing IDs or
/// racing to consume one another's results.
final class NativeCookieStore {
  static int _nextRequestId = 1;
  static final Map<int, _PendingCookieOperation<Object?>> _pending =
      <int, _PendingCookieOperation<Object?>>{};
  static Timer? _pollTimer;

  /// Adds or replaces one session cookie in the shared WPE store.
  Future<void> setCookie(NativeCookie cookie) async {
    final name = cookie.name.toNativeUtf8();
    final value = cookie.value.toNativeUtf8();
    final domain = cookie.domain.toNativeUtf8();
    final path = cookie.path.toNativeUtf8();
    try {
      await _submit<Object?>(
        start: (requestId) => webviewFlutterLinuxCookieSet(
          requestId,
          name.cast(),
          value.cast(),
          domain.cast(),
          path.cast(),
        ),
        decode: (_) => null,
      );
    } finally {
      calloc
        ..free(name)
        ..free(value)
        ..free(domain)
        ..free(path);
    }
  }

  /// Returns cookies WPE associates with the supplied HTTP(S) [url].
  Future<List<NativeCookie>> getCookies(Uri url) async {
    final nativeUrl = url.toString().toNativeUtf8();
    try {
      return await _submit<List<NativeCookie>>(
        start: (requestId) =>
            webviewFlutterLinuxCookieGet(requestId, nativeUrl.cast()),
        decode: (result) => result.cookies,
      );
    } finally {
      calloc.free(nativeUrl);
    }
  }

  /// Clears every cookie and reports whether the jar was previously non-empty.
  Future<bool> clearCookies() => _submit<bool>(
    start: webviewFlutterLinuxCookieClear,
    decode: (result) => result.hadCookies ?? false,
  );

  /// Sets WPE's application-wide cookie acceptance policy.
  Future<void> setAcceptPolicy(int policy) async {
    final status = webviewFlutterLinuxCookieSetAcceptPolicy(policy);
    if (status != 0) {
      throw StateError(
        'Native cookie accept-policy update failed with status $status.',
      );
    }
  }

  /// Returns WPE's effective application-wide cookie acceptance policy.
  Future<int> getAcceptPolicy() => _submit<int>(
    start: webviewFlutterLinuxCookieGetAcceptPolicy,
    decode: (result) {
      final policy = result.acceptPolicy;
      if (policy == null) {
        throw StateError('Native cookie policy result did not carry a policy.');
      }
      return policy;
    },
  );

  /// Enables or disables Intelligent Tracking Prevention for the shared WPE
  /// network session.
  Future<void> setIntelligentTrackingPreventionEnabled(bool enabled) async {
    final status = webviewFlutterLinuxCookieSetItpEnabled(enabled ? 1 : 0);
    if (status != 0) {
      throw StateError('Native ITP update failed with status $status.');
    }
  }

  /// Returns whether Intelligent Tracking Prevention is enabled for the shared
  /// WPE network session.
  Future<bool> isIntelligentTrackingPreventionEnabled() async {
    final enabled = webviewFlutterLinuxCookieItpEnabled();
    if (enabled < 0) {
      throw StateError('Native ITP lookup failed with status $enabled.');
    }
    return enabled != 0;
  }

  static Future<T> _submit<T>({
    required int Function(int requestId) start,
    required T Function(_NativeCookieResult result) decode,
  }) {
    final requestId = _allocateRequestId();
    final completer = Completer<T>();
    _pending[requestId] =
        _PendingCookieOperation<T>(completer: completer, decode: decode)
            as _PendingCookieOperation<Object?>;
    final status = start(requestId);
    if (status != 0) {
      _pending.remove(requestId);
      completer.completeError(
        StateError('Native cookie operation failed with status $status.'),
      );
      return completer.future;
    }
    _ensurePolling();
    return completer.future;
  }

  static int _allocateRequestId() {
    final requestId = _nextRequestId;
    _nextRequestId = requestId == 0x7fffffffffffffff ? 1 : requestId + 1;
    return requestId;
  }

  static void _ensurePolling() {
    _pollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _drainResults(),
    );
    scheduleMicrotask(_drainResults);
  }

  static void _drainResults() {
    while (webviewFlutterLinuxCookieResultCount() > 0) {
      _NativeCookieResult result;
      try {
        result = _takeOldestResult();
      } catch (error, stackTrace) {
        final requestId = webviewFlutterLinuxCookieResultRequestId();
        webviewFlutterLinuxCookieResultPop();
        _pending.remove(requestId)?.completer.completeError(error, stackTrace);
        continue;
      }
      final operation = _pending.remove(result.requestId);
      if (operation == null) continue;
      if (result.status != 0) {
        operation.completer.completeError(
          PlatformException(
            code: 'cookie_error',
            message: result.error.isEmpty
                ? 'WPE cookie operation failed.'
                : result.error,
          ),
        );
        continue;
      }
      try {
        operation.completer.complete(operation.decode(result));
      } catch (error, stackTrace) {
        operation.completer.completeError(error, stackTrace);
      }
    }
    if (_pending.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  static _NativeCookieResult _takeOldestResult() {
    final requestId = webviewFlutterLinuxCookieResultRequestId();
    final status = webviewFlutterLinuxCookieResultStatus();
    final hadCookiesValue = webviewFlutterLinuxCookieResultHadCookies();
    final acceptPolicyValue = webviewFlutterLinuxCookieResultAcceptPolicy();
    final error = _copyError();
    final cookieCount = webviewFlutterLinuxCookieResultCookieCount();
    final cookies = <NativeCookie>[
      for (var index = 0; index < cookieCount; index += 1)
        NativeCookie(
          name: _copyField(index, 0),
          value: _copyField(index, 1),
          domain: _copyField(index, 2),
          path: _copyField(index, 3),
        ),
    ];
    final popStatus = webviewFlutterLinuxCookieResultPop();
    if (popStatus != 0) {
      throw StateError('Native cookie result pop failed: $popStatus.');
    }
    return _NativeCookieResult(
      requestId: requestId,
      status: status,
      hadCookies: hadCookiesValue < 0 ? null : hadCookiesValue != 0,
      acceptPolicy: acceptPolicyValue < 0 ? null : acceptPolicyValue,
      error: error,
      cookies: cookies,
    );
  }

  static String _copyError() {
    final length = webviewFlutterLinuxCookieResultErrorLength();
    return _copyUtf8(
      length,
      (destination) =>
          webviewFlutterLinuxCookieResultCopyError(destination, length),
    );
  }

  static String _copyField(int cookieIndex, int field) {
    final length = webviewFlutterLinuxCookieResultFieldLength(
      cookieIndex,
      field,
    );
    return _copyUtf8(
      length,
      (destination) => webviewFlutterLinuxCookieResultCopyField(
        cookieIndex,
        field,
        destination,
        length,
      ),
    );
  }

  static String _copyUtf8(
    int length,
    int Function(ffi.Pointer<ffi.Uint8> destination) copy,
  ) {
    final destination = calloc<ffi.Uint8>(length == 0 ? 1 : length);
    try {
      final copied = copy(destination);
      if (copied != length) {
        throw StateError(
          'Native cookie result copy returned $copied for $length bytes.',
        );
      }
      return utf8.decode(destination.asTypedList(length));
    } finally {
      calloc.free(destination);
    }
  }
}
