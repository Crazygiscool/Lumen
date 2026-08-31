// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'linux_navigation_delegate.dart';
import 'linux_webview_controller.dart';
import 'linux_webview_cookie_manager.dart';
import 'linux_webview_widget.dart';

/// WPE WebKit implementation of the `webview_flutter` platform interface.
///
/// Controllers create their native WPE view lazily when either a native-backed
/// API or a presenting widget first needs it. Widgets lease the controller's
/// renderer and connect its frames to a Flutter texture without owning the
/// browser lifetime.
class WebViewFlutterLinux extends WebViewPlatform {
  /// Installs [WebViewFlutterLinux] as the active platform implementation.
  ///
  /// Flutter calls this entry point through the package's federated plugin
  /// registration metadata.
  static void registerWith() {
    WebViewPlatform.instance = WebViewFlutterLinux();
  }

  /// Creates a controller whose native WebView is allocated on first use.
  @override
  LinuxWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => LinuxWebViewController(params);

  /// Creates storage for navigation callbacks used by a Linux controller.
  @override
  LinuxNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => LinuxNavigationDelegate(params);

  /// Creates the widget delegate that displays the native browser texture.
  @override
  LinuxWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => LinuxWebViewWidget(params);

  /// Creates the application-wide WPE cookie-manager delegate.
  @override
  LinuxWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => LinuxWebViewCookieManager(params);
}
