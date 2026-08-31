// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Stores navigation callbacks used by the Linux WebView implementation.
///
/// The controller reports controller-request decisions and native WebKit URL,
/// lifecycle, and progress events. The remaining callbacks are retained here
/// so error and authentication events can be added without changing the public
/// platform-delegate contract.
class LinuxNavigationDelegate extends PlatformNavigationDelegate {
  /// Creates a delegate for the supplied platform-interface parameters.
  // ignore: use_super_parameters
  LinuxNavigationDelegate(PlatformNavigationDelegateCreationParams params)
    : super.implementation(params);

  /// Invoked before a controller-initiated main-frame navigation.
  NavigationRequestCallback? onNavigationRequest;

  /// Invoked when WebKit starts a main-frame navigation.
  PageEventCallback? onPageStarted;

  /// Invoked when WebKit finishes loading the main frame and its resources.
  PageEventCallback? onPageFinished;

  /// Receives WebKit responses with HTTP status codes from 400 through 599.
  HttpResponseErrorCallback? onHttpError;

  /// Receives WebKit's estimated load progress values.
  ProgressCallback? onProgress;

  /// Receives main-document and subordinate-resource failures from WebKit.
  WebResourceErrorCallback? onWebResourceError;

  /// Invoked when WebKit reports a different main-frame URL.
  UrlChangeCallback? onUrlChange;

  /// Receives HTTP authentication challenges retained by WPE.
  HttpAuthRequestCallback? onHttpAuthRequest;

  /// Receives TLS certificate failures retained by WPE.
  SslAuthErrorCallback? onSslAuthError;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    this.onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    this.onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {
    this.onHttpError = onHttpError;
  }

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {
    this.onProgress = onProgress;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    this.onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {
    this.onUrlChange = onUrlChange;
  }

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {
    this.onHttpAuthRequest = onHttpAuthRequest;
  }

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback onSslAuthError) async {
    this.onSslAuthError = onSslAuthError;
  }
}
