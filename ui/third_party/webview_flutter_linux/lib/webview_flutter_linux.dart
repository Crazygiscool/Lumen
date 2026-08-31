// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A WPE WebKit implementation of `webview_flutter` for Linux.
///
/// Applications use the platform-independent API from `package:webview_flutter`.
/// Flutter loads this package through federated plugin registration and renders
/// each browser instance into a Flutter texture.
library;

export 'src/linux_navigation_delegate.dart';
export 'src/linux_webview_controller.dart';
export 'src/linux_webview_cookie_manager.dart';
export 'src/linux_webview_download.dart';
export 'src/linux_webview_geolocation.dart';
export 'src/linux_webview_platform.dart';
export 'src/linux_webview_widget.dart';
