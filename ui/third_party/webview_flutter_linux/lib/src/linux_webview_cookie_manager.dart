// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'native_cookie_store.dart';

/// WPE's application-wide cookie acceptance policy.
enum LinuxCookieAcceptPolicy {
  /// Accept first-party and third-party cookies unconditionally.
  always(0),

  /// Reject every cookie unconditionally.
  never(1),

  /// Accept cookies only when they are set by the main document.
  ///
  /// WPE temporarily reports and applies [always] while Intelligent Tracking
  /// Prevention is enabled, because ITP makes adaptive third-party-cookie
  /// decisions. Disabling ITP restores this strict policy.
  noThirdParty(2);

  const LinuxCookieAcceptPolicy(this.nativeValue);

  /// Integer value used by WPE's `WebKitCookieAcceptPolicy` ABI.
  final int nativeValue;

  /// Decodes a value returned by WPE.
  static LinuxCookieAcceptPolicy fromNativeValue(int value) => switch (value) {
    0 => always,
    1 => never,
    2 => noThirdParty,
    _ => throw StateError('Unknown WPE cookie accept policy: $value.'),
  };
}

/// Application-wide WPE cookie manager for every Linux WebView.
///
/// Operations may run before a WebView is mounted. WPE's default network
/// session is shared by the cookie manager and all subsequently created views.
class LinuxWebViewCookieManager extends PlatformWebViewCookieManager {
  /// Creates a manager backed by WPE's application-scoped network session.
  // ignore: use_super_parameters
  LinuxWebViewCookieManager(PlatformWebViewCookieManagerCreationParams params)
    : super.implementation(params);

  final NativeCookieStore _store = NativeCookieStore();

  @override
  Future<bool> clearCookies() => _store.clearCookies();

  @override
  Future<void> setCookie(WebViewCookie cookie) {
    if (!_isValidCookiePath(cookie.path)) {
      throw ArgumentError.value(
        cookie.path,
        'cookie.path',
        'Must contain only RFC 6265 cookie-path characters.',
      );
    }
    return _store.setCookie(
      NativeCookie(
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path,
      ),
    );
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw ArgumentError.value(
        url,
        'url',
        'WPE cookie lookup requires an HTTP or HTTPS URL.',
      );
    }
    return <WebViewCookie>[
      for (final cookie in await _store.getCookies(url))
        WebViewCookie(
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain,
          path: cookie.path,
        ),
    ];
  }

  /// Sets the cookie policy for every Linux WebView in this application.
  ///
  /// This is application-wide because WPE stores the policy on the shared
  /// network session's cookie manager. Existing and subsequently created
  /// WebViews observe the same value.
  Future<void> setCookieAcceptPolicy(LinuxCookieAcceptPolicy policy) =>
      _store.setAcceptPolicy(policy.nativeValue);

  /// Returns WPE's effective application-wide cookie policy.
  ///
  /// When ITP is enabled after [noThirdParty] was selected, WPE reports
  /// [LinuxCookieAcceptPolicy.always] while retaining the stricter selection
  /// for restoration when ITP is disabled.
  Future<LinuxCookieAcceptPolicy> getCookieAcceptPolicy() async =>
      LinuxCookieAcceptPolicy.fromNativeValue(await _store.getAcceptPolicy());

  /// Sets whether third-party cookies are accepted by Linux WebViews.
  ///
  /// This mirrors Android's boolean convenience API, but applies to the shared
  /// WPE session rather than one controller. `true` selects
  /// [LinuxCookieAcceptPolicy.always]; `false` selects
  /// [LinuxCookieAcceptPolicy.noThirdParty]. Disable ITP as well when strict,
  /// unconditional third-party rejection is required.
  Future<void> setAcceptThirdPartyCookies(bool accept) => setCookieAcceptPolicy(
    accept
        ? LinuxCookieAcceptPolicy.always
        : LinuxCookieAcceptPolicy.noThirdParty,
  );

  /// Enables or disables WPE Intelligent Tracking Prevention application-wide.
  ///
  /// ITP collects resource-load statistics and adaptively decides whether to
  /// allow third-party cookies. While enabled, WPE does not enforce the strict
  /// [LinuxCookieAcceptPolicy.noThirdParty] policy.
  Future<void> setIntelligentTrackingPreventionEnabled(bool enabled) =>
      _store.setIntelligentTrackingPreventionEnabled(enabled);

  /// Returns whether WPE Intelligent Tracking Prevention is enabled.
  Future<bool> isIntelligentTrackingPreventionEnabled() =>
      _store.isIntelligentTrackingPreventionEnabled();

  bool _isValidCookiePath(String path) {
    for (final character in path.codeUnits) {
      if ((character < 0x20 || character > 0x3a) &&
          (character < 0x3c || character > 0x7e)) {
        return false;
      }
    }
    return true;
  }
}
