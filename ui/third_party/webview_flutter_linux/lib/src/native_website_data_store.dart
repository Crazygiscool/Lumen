// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'native_frame_bindings.dart';

/// Request-scoped bridge to WPE's application-wide website-data manager.
///
/// Website data belongs to the application-scoped WebKit network session, not to a
/// particular rendered view. This store therefore uses handle-free native
/// operations and can clear cache or storage before any [WebViewWidget] has
/// attached. One shared instance coordinates request IDs across every Linux
/// controller, while injected functions make queue behavior independently
/// testable without starting WPE.
final class NativeWebsiteDataStore {
  /// Creates a bridge using the production native ABI by default.
  NativeWebsiteDataStore({
    int Function(int requestId, int types)? start,
    int Function()? resultCount,
    int Function()? resultRequestId,
    int Function()? resultStatus,
    int Function()? resultErrorLength,
    int Function(ffi.Pointer<ffi.Uint8> destination, int length)?
    copyResultError,
    int Function()? popResult,
  }) : _start = start ?? webviewFlutterLinuxWebsiteDataClear,
       _resultCount = resultCount ?? webviewFlutterLinuxWebsiteDataResultCount,
       _resultRequestId =
           resultRequestId ?? webviewFlutterLinuxWebsiteDataResultRequestId,
       _resultStatus =
           resultStatus ?? webviewFlutterLinuxWebsiteDataResultStatus,
       _resultErrorLength =
           resultErrorLength ?? webviewFlutterLinuxWebsiteDataResultErrorLength,
       _copyResultError =
           copyResultError ?? webviewFlutterLinuxWebsiteDataResultCopyError,
       _popResult = popResult ?? webviewFlutterLinuxWebsiteDataResultPop;

  /// Shared store used by every Linux controller in the process.
  static final NativeWebsiteDataStore shared = NativeWebsiteDataStore();

  final int Function(int requestId, int types) _start;
  final int Function() _resultCount;
  final int Function() _resultRequestId;
  final int Function() _resultStatus;
  final int Function() _resultErrorLength;
  final int Function(ffi.Pointer<ffi.Uint8> destination, int length)
  _copyResultError;
  final int Function() _popResult;

  int _nextRequestId = 1;
  final Map<int, Completer<void>> _pending = <int, Completer<void>>{};
  Timer? _pollTimer;

  /// Clears the selected `WebKitWebsiteDataTypes` and awaits native completion.
  Future<void> clear(int types) {
    if (types == 0) {
      return Future<void>.error(
        ArgumentError.value(types, 'types', 'Must select website data.'),
      );
    }
    final requestId = _allocateRequestId();
    final completer = Completer<void>();
    _pending[requestId] = completer;
    final status = _start(requestId, types);
    if (status != 0) {
      _pending.remove(requestId);
      completer.completeError(
        StateError('Native website-data clear failed with status $status.'),
      );
      return completer.future;
    }
    _ensurePolling();
    return completer.future;
  }

  int _allocateRequestId() {
    final requestId = _nextRequestId;
    _nextRequestId = requestId == 0x7fffffffffffffff ? 1 : requestId + 1;
    return requestId;
  }

  void _ensurePolling() {
    _pollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _drainResults(),
    );
    scheduleMicrotask(_drainResults);
  }

  void _drainResults() {
    while (_resultCount() > 0) {
      final requestId = _resultRequestId();
      var popped = false;
      try {
        final status = _resultStatus();
        final error = _copyError();
        final popStatus = _popResult();
        if (popStatus != 0) {
          throw StateError(
            'Native website-data result pop failed: $popStatus.',
          );
        }
        popped = true;
        final completer = _pending.remove(requestId);
        if (completer == null) continue;
        if (status == 0) {
          completer.complete();
        } else {
          completer.completeError(
            PlatformException(
              code: 'website_data_error',
              message: error.isEmpty ? 'WPE website-data clear failed.' : error,
            ),
          );
        }
      } catch (error, stackTrace) {
        if (!popped) _popResult();
        _pending.remove(requestId)?.completeError(error, stackTrace);
      }
    }
    if (_pending.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  String _copyError() {
    final length = _resultErrorLength();
    final destination = calloc<ffi.Uint8>(length == 0 ? 1 : length);
    try {
      final copied = _copyResultError(destination, length);
      if (copied != length) {
        throw StateError(
          'Native website-data error copy returned $copied for $length bytes.',
        );
      }
      return utf8.decode(destination.asTypedList(length));
    } finally {
      calloc.free(destination);
    }
  }
}
