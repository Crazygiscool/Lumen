// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'linux_navigation_delegate.dart';
import 'linux_webview_download.dart';
import 'native_frame_renderer.dart';
import 'native_website_data_store.dart';
import 'webview_attachment_lease.dart';

/// Converts the JavaScript scroll-position tuple into Flutter coordinates.
Offset decodeJavaScriptScrollPosition(Object result) {
  if (result case <Object?>[num x, num y]) {
    return Offset(x.toDouble(), y.toDouble());
  }
  throw StateError('JavaScript returned an invalid scroll position: $result');
}

/// Adapts JavaScriptCore values to the common Linux WebView result contract.
///
/// Android's `evaluateJavascript` API exposes JavaScript strings and nullish
/// values as JSON text, and the platform-independent integration suite relies
/// on that representation for non-WKWebView implementations. WPE gives this
/// plugin already-decoded JavaScriptCore values, so strings are encoded once
/// and nullish values become the JSON literal while numbers, booleans, arrays,
/// and objects retain their useful Dart representation.
@visibleForTesting
Object normalizeJavaScriptResult(Object? result) => switch (result) {
  null => 'null',
  String value => jsonEncode(value),
  _ => result,
};

/// Effective WPE settings and host-build support for optional capabilities.
@immutable
final class LinuxWebViewCapabilityState {
  /// Decodes the stable bit field returned by the native WPE bridge.
  const LinuxWebViewCapabilityState.fromFlags(int flags)
    : inlineMediaPlaybackEnabled = flags & (1 << 0) != 0,
      webRtcSettingEnabled = flags & (1 << 1) != 0,
      encryptedMediaSettingEnabled = flags & (1 << 2) != 0,
      fileAccessFromFileUrlsEnabled = flags & (1 << 3) != 0,
      universalAccessFromFileUrlsEnabled = flags & (1 << 4) != 0,
      javaScriptClipboardAccessEnabled = flags & (1 << 5) != 0,
      webRtcSupportedByHost = flags & (1 << 8) != 0,
      encryptedMediaSupportedByHost = flags & (1 << 9) != 0;

  /// Whether WPE currently allows media elements to play inline.
  final bool inlineMediaPlaybackEnabled;

  /// Whether the per-view WebRTC preference is currently enabled.
  final bool webRtcSettingEnabled;

  /// Whether the per-view encrypted-media preference is currently enabled.
  final bool encryptedMediaSettingEnabled;

  /// Whether a local-file document may request other local files.
  final bool fileAccessFromFileUrlsEnabled;

  /// Whether a local-file document may access arbitrary origins.
  final bool universalAccessFromFileUrlsEnabled;

  /// Whether page JavaScript may execute clipboard editing commands.
  final bool javaScriptClipboardAccessEnabled;

  /// Whether the installed WPE build contains its peer-connection feature.
  final bool webRtcSupportedByHost;

  /// Whether the installed WPE build contains its encrypted-media feature.
  final bool encryptedMediaSupportedByHost;
}

/// Maps stable WPE WebKit network codes to the federated error categories.
WebResourceErrorType? webResourceErrorTypeForWpeCode(int code) {
  return switch (code) {
    300 => WebResourceErrorType.connect,
    301 => WebResourceErrorType.unsupportedScheme,
    303 => WebResourceErrorType.fileNotFound,
    100 || 101 => WebResourceErrorType.unsupportedScheme,
    _ => null,
  };
}

/// Builds a readable description from GLib `GTlsCertificateFlags` bits.
String tlsErrorDescriptionForWpeFlags(int flags) {
  final problems = <String>[
    if (flags & (1 << 0) != 0) 'unknown certificate authority',
    if (flags & (1 << 1) != 0) 'certificate identity does not match the host',
    if (flags & (1 << 2) != 0) 'certificate is not yet valid',
    if (flags & (1 << 3) != 0) 'certificate has expired',
    if (flags & (1 << 4) != 0) 'certificate has been revoked',
    if (flags & (1 << 5) != 0) 'certificate uses an insecure algorithm',
    if (flags & (1 << 6) != 0) 'generic certificate validation failure',
    if (flags & ~((1 << 7) - 1) != 0) 'unknown certificate validation error',
  ];
  return problems.isEmpty
      ? 'TLS certificate validation failed.'
      : 'TLS certificate validation failed: ${problems.join(', ')}.';
}

/// Selection modes exposed by WPE for HTML file inputs.
enum LinuxFileSelectorMode {
  /// Select exactly one existing file.
  open,

  /// Select one or more existing files.
  openMultiple,
}

/// Parameters supplied when page content opens an HTML file input.
final class LinuxFileSelectorParams {
  /// Creates an immutable description of one browser file chooser request.
  LinuxFileSelectorParams({
    required this.mode,
    required List<String> acceptedMimeTypes,
    required List<String> initialFiles,
  }) : acceptedMimeTypes = List<String>.unmodifiable(acceptedMimeTypes),
       initialFiles = List<String>.unmodifiable(initialFiles);

  /// Whether the page accepts one file or multiple files.
  final LinuxFileSelectorMode mode;

  /// MIME types requested by the input's `accept` attribute.
  final List<String> acceptedMimeTypes;

  /// Files selected during a previous invocation, when available from WebKit.
  final List<String> initialFiles;
}

/// Decides whether the application accepts ownership of a related WebView.
///
/// Returning `true` transfers the popup to application code. It should render
/// `WebViewController.fromPlatform(request.platformController)` in a
/// `WebViewWidget`, and later call [LinuxWebViewPopupRequest.dispose] if the
/// widget is never mounted. Returning `false` or throwing disposes the child
/// immediately. When no callback is registered, URL-backed popup requests
/// navigate the opener to preserve the platform-independent WebView behavior.
typedef LinuxWebViewPopupCallback =
    FutureOr<bool> Function(LinuxWebViewPopupRequest request);

/// Observes effective HTML fullscreen state changes for a Linux WebView.
typedef LinuxWebViewFullscreenChangedCallback =
    void Function(bool isFullscreen);

/// An independently renderable WebKit view created by `target="_blank"` or
/// `window.open()`.
///
/// The child shares its opener's WebKit process and network session, as required
/// by WebKit, but owns a distinct Flutter texture and Linux platform controller.
/// [onCloseRequested] completes when page script calls `window.close()`. The
/// application remains responsible for removing its Flutter UI and disposing
/// the request, matching WebKit's owner-managed window lifecycle.
final class LinuxWebViewPopupRequest {
  LinuxWebViewPopupRequest._({
    required this.requestedUrl,
    required this.platformController,
  });

  /// URL from the navigation action, or null for an initially blank window.
  final Uri? requestedUrl;

  /// Platform controller to wrap with `WebViewController.fromPlatform`.
  final LinuxWebViewController platformController;

  final Completer<void> _closeRequested = Completer<void>();

  /// Completes once when WebKit asks the application to close this child.
  Future<void> get onCloseRequested => _closeRequested.future;

  /// Whether WebKit has already requested that this child be closed.
  bool get isCloseRequested => _closeRequested.isCompleted;

  /// Whether the popup's native view has been released.
  bool get isDisposed => platformController.isDisposed;

  /// Releases the popup if it is unmounted or no longer displayed.
  ///
  /// Remove its `WebViewWidget` before calling this method. The operation is
  /// idempotent and safe to call during surrounding UI teardown.
  void dispose() => platformController._disposePopup();

  void _didRequestClose() {
    if (!_closeRequested.isCompleted) _closeRequested.complete();
  }
}

/// WPE-specific permission resources beyond the common camera and microphone.
class LinuxWebViewPermissionResourceType extends WebViewPermissionResourceType {
  const LinuxWebViewPermissionResourceType._(super.name);

  /// A monitor, window, or application surface requested for screen sharing.
  static const LinuxWebViewPermissionResourceType displayCapture =
      LinuxWebViewPermissionResourceType._('displayCapture');

  /// The user's physical location.
  static const LinuxWebViewPermissionResourceType geolocation =
      LinuxWebViewPermissionResourceType._('geolocation');

  /// Permission to display web notifications.
  static const LinuxWebViewPermissionResourceType notifications =
      LinuxWebViewPermissionResourceType._('notifications');

  /// Permission to enumerate available media devices.
  static const LinuxWebViewPermissionResourceType deviceInfo =
      LinuxWebViewPermissionResourceType._('deviceInfo');

  /// Permission to use an encrypted-media key system.
  static const LinuxWebViewPermissionResourceType protectedMedia =
      LinuxWebViewPermissionResourceType._('protectedMedia');

  /// Permission for an embedded origin to access its unpartitioned data.
  static const LinuxWebViewPermissionResourceType websiteDataAccess =
      LinuxWebViewPermissionResourceType._('websiteDataAccess');

  /// Permission to start an immersive WebXR session.
  static const LinuxWebViewPermissionResourceType xr =
      LinuxWebViewPermissionResourceType._('xr');

  /// A newer WPE permission type unknown to this Dart package version.
  static const LinuxWebViewPermissionResourceType unknown =
      LinuxWebViewPermissionResourceType._('unknown');
}

/// Decodes the stable permission-resource bitmask supplied by the Rust bridge.
Set<WebViewPermissionResourceType> decodeNativePermissionResourceTypes(
  int mask,
) {
  const knownMask = (1 << 9) - 1;
  final types = <WebViewPermissionResourceType>{
    if (mask & (1 << 0) != 0) WebViewPermissionResourceType.camera,
    if (mask & (1 << 1) != 0) WebViewPermissionResourceType.microphone,
    if (mask & (1 << 2) != 0) LinuxWebViewPermissionResourceType.displayCapture,
    if (mask & (1 << 3) != 0) LinuxWebViewPermissionResourceType.geolocation,
    if (mask & (1 << 4) != 0) LinuxWebViewPermissionResourceType.notifications,
    if (mask & (1 << 5) != 0) LinuxWebViewPermissionResourceType.deviceInfo,
    if (mask & (1 << 6) != 0) LinuxWebViewPermissionResourceType.protectedMedia,
    if (mask & (1 << 7) != 0)
      LinuxWebViewPermissionResourceType.websiteDataAccess,
    if (mask & (1 << 8) != 0) LinuxWebViewPermissionResourceType.xr,
    if (mask & ~knownMask != 0 || mask == 0)
      LinuxWebViewPermissionResourceType.unknown,
  };
  return Set<WebViewPermissionResourceType>.unmodifiable(types);
}

/// Linux implementation of a permission request retained by WPE.
class LinuxWebViewPermissionRequest extends PlatformWebViewPermissionRequest {
  /// Creates a request whose response is forwarded through [onDecision].
  LinuxWebViewPermissionRequest({
    required super.types,
    required Future<void> Function(bool allow) onDecision,
  }) : _onDecision = onDecision;

  final Future<void> Function(bool allow) _onDecision;
  final Completer<void> _resolution = Completer<void>();

  /// Whether either [grant] or [deny] has already been called.
  bool get isResolved => _resolution.isCompleted;

  @override
  Future<void> grant() => _resolve(true);

  @override
  Future<void> deny() => _resolve(false);

  Future<void> _resolve(bool allow) {
    if (_resolution.isCompleted) {
      return Future<void>.error(
        StateError('This WebView permission request was already resolved.'),
      );
    }
    try {
      _resolution.complete(_onDecision(allow));
    } catch (error, stackTrace) {
      _resolution.completeError(error, stackTrace);
    }
    return _resolution.future;
  }
}

/// Presents one page-created Web Notification through application-owned UI.
typedef LinuxWebViewNotificationCallback =
    FutureOr<void> Function(LinuxWebViewNotification notification);

/// A Web Notification retained by WPE while Flutter presents it.
///
/// The package deliberately does not choose a desktop notification toolkit.
/// Applications may render an in-app surface or delegate to their preferred
/// system-notification package. [click] reports activation to page JavaScript
/// without closing the notification; [close] withdraws it. [onClosed]
/// completes when either Flutter or the page closes it, including navigation.
class LinuxWebViewNotification {
  /// Creates a notification backed by native click and close operations.
  @visibleForTesting
  LinuxWebViewNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.tag,
    required this.url,
    required Future<void> Function() onClick,
    required Future<void> Function() onClose,
  }) : _onClick = onClick,
       _onClose = onClose;

  /// Handle-scoped identifier suitable for application UI keys.
  final int id;

  /// Page-supplied notification title.
  final String title;

  /// Page-supplied notification body.
  final String body;

  /// Optional tag used by pages to group or replace notifications.
  final String? tag;

  /// Page URL active when WebKit created this notification.
  final Uri? url;

  final Future<void> Function() _onClick;
  final Future<void> Function() _onClose;
  final Completer<void> _closed = Completer<void>();
  bool _clicked = false;

  /// Whether activation has already been reported to WebKit.
  bool get isClicked => _clicked;

  /// Whether WebKit has withdrawn the notification.
  bool get isClosed => _closed.isCompleted;

  /// Completes when Flutter, page script, or navigation closes the notification.
  Future<void> get onClosed => _closed.future;

  /// Reports one user activation while leaving the notification active.
  Future<void> click() {
    if (isClosed) {
      return Future<void>.error(
        StateError('This WebView notification is already closed.'),
      );
    }
    if (_clicked) {
      return Future<void>.error(
        StateError('This WebView notification was already clicked.'),
      );
    }
    _clicked = true;
    return Future<void>.sync(_onClick);
  }

  /// Withdraws the notification; repeated closes are harmless.
  Future<void> close() {
    if (isClosed) return Future<void>.value();
    _didClose();
    return Future<void>.sync(_onClose);
  }

  void _didClose() {
    if (!_closed.isCompleted) _closed.complete();
  }
}

/// Linux HTTP-authentication request with an exactly-once response contract.
///
/// The federated interface exposes response callbacks so applications may show
/// asynchronous Flutter UI and invoke either callback later. WPE retains the
/// challenge until that happens. Calling both callbacks, or calling either one
/// more than once, throws instead of attempting to resolve a released native
/// request.
class LinuxHttpAuthRequest extends HttpAuthRequest {
  /// Creates a request whose response is forwarded to the native bridge.
  factory LinuxHttpAuthRequest({
    required String host,
    required String? realm,
    required void Function(WebViewCredential credential) onProceed,
    required void Function() onCancel,
  }) {
    final decision = _LinuxHttpAuthDecision(
      onProceed: onProceed,
      onCancel: onCancel,
    );
    return LinuxHttpAuthRequest._(host: host, realm: realm, decision: decision);
  }

  LinuxHttpAuthRequest._({
    required super.host,
    required super.realm,
    required _LinuxHttpAuthDecision decision,
  }) : _decision = decision,
       super(onProceed: decision.proceed, onCancel: decision.cancel);

  final _LinuxHttpAuthDecision _decision;

  /// Whether credentials or cancellation have already been submitted.
  bool get isResolved => _decision.isResolved;
}

final class _LinuxHttpAuthDecision {
  _LinuxHttpAuthDecision({required this.onProceed, required this.onCancel});

  final void Function(WebViewCredential credential) onProceed;
  final void Function() onCancel;
  bool isResolved = false;

  void proceed(WebViewCredential credential) {
    _beginResolution();
    onProceed(credential);
  }

  void cancel() {
    _beginResolution();
    onCancel();
  }

  void _beginResolution() {
    if (isResolved) {
      throw StateError(
        'This HTTP authentication request was already resolved.',
      );
    }
    isResolved = true;
  }
}

/// Linux implementation of a retained TLS certificate error.
///
/// WPE has already stopped the failed request. [proceed] installs an exception
/// for the reported certificate and host and reloads [url], while [cancel]
/// releases the retained request. Exactly one decision is accepted.
class LinuxSslAuthError extends PlatformSslAuthError {
  /// Creates an error whose decision is forwarded through [onDecision].
  LinuxSslAuthError({
    required super.certificate,
    required super.description,
    required this.url,
    required this.errorFlags,
    required Future<void> Function(bool proceed) onDecision,
  }) : _onDecision = onDecision;

  /// URL whose TLS certificate validation failed.
  final String url;

  /// GLib `GTlsCertificateFlags` bitmask reported by WPE.
  final int errorFlags;

  final Future<void> Function(bool proceed) _onDecision;
  final Completer<void> _resolution = Completer<void>();

  /// Whether either [proceed] or [cancel] has already been called.
  bool get isResolved => _resolution.isCompleted;

  @override
  Future<void> proceed() => _resolve(true);

  @override
  Future<void> cancel() => _resolve(false);

  Future<void> _resolve(bool proceed) {
    if (_resolution.isCompleted) {
      return Future<void>.error(
        StateError('This TLS certificate error was already resolved.'),
      );
    }
    try {
      _resolution.complete(_onDecision(proceed));
    } catch (error, stackTrace) {
      _resolution.completeError(error, stackTrace);
    }
    return _resolution.future;
  }
}

const String _eventBridgeChannel = '__webviewFlutterLinuxEvents_0_1';
const String _deferredInitialUrl =
    'about:blank#webview_flutter_linux_deferred_load';

const String _eventBridgeScript = r'''
(() => {
  const marker = '__webviewFlutterLinuxEventBridgeInstalled_0_1';
  if (window[marker]) return;
  const bridge = window['__webviewFlutterLinuxEvents_0_1'];
  if (!bridge) return;
  Object.defineProperty(window, marker, {value: true});
  const send = value => bridge.postMessage(JSON.stringify(value));
  const stringifyWithoutCycles = value => {
    const ancestors = [];
    return JSON.stringify(value, function(_, candidate) {
      if (candidate === null || typeof candidate !== 'object') {
        return candidate;
      }
      while (
        ancestors.length > 0 &&
        ancestors[ancestors.length - 1] !== this
      ) {
        ancestors.pop();
      }
      if (ancestors.includes(candidate)) return undefined;
      ancestors.push(candidate);
      return candidate;
    });
  };
  const render = value => {
    if (typeof value === 'string') return value;
    try {
      const encoded = stringifyWithoutCycles(value);
      return encoded === undefined ? String(value) : encoded;
    } catch (_) {
      return String(value);
    }
  };
  for (const [method, level] of Object.entries({
    error: 'error', warn: 'warning', debug: 'debug',
    info: 'info', log: 'log'
  })) {
    const original = console[method].bind(console);
    console[method] = (...values) => {
      original(...values);
      send({type: 'console', level, message: values.map(render).join(' ')});
    };
  }
  if (window === window.top) {
    let scheduled = false;
    addEventListener('scroll', () => {
      if (scheduled) return;
      scheduled = true;
      requestAnimationFrame(() => {
        scheduled = false;
        send({type: 'scroll', x: window.scrollX, y: window.scrollY});
      });
    }, {passive: true});
  }
})();
''';

final RegExp _httpHeaderNamePattern = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

/// Resolves a declared Flutter asset inside the standard Linux app bundle.
///
/// The Linux runner places the executable beside `data/flutter_assets`. Asset
/// keys are relative paths in that directory. Rejecting absolute and parent
/// paths ensures this resolver cannot escape the packaged asset root.
@visibleForTesting
Uri resolveLinuxFlutterAssetUri({
  required String executablePath,
  required String assetKey,
}) {
  final segments = assetKey.split('/');
  if (assetKey.isEmpty ||
      assetKey.startsWith('/') ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw ArgumentError.value(
      assetKey,
      'assetKey',
      'Must be a non-empty relative Flutter asset key without parent paths.',
    );
  }
  final assetRoot = File(
    executablePath,
  ).absolute.parent.uri.resolve('data/flutter_assets/');
  return assetRoot.resolveUri(Uri(path: assetKey));
}

final class _LinuxHistoryEntry {
  _LinuxHistoryEntry(
    this.url,
    Map<String, String> headers, {
    this.html,
    this.baseUrl,
    this.method = LoadRequestMethod.get,
    Uint8List? body,
  }) : headers = Map<String, String>.unmodifiable(headers),
       body = body == null ? null : Uint8List.fromList(body);

  final String url;
  final Map<String, String> headers;
  final String? html;
  final String? baseUrl;
  final LoadRequestMethod method;
  final Uint8List? body;

  _LinuxHistoryEntry withUrl(String nextUrl) => _LinuxHistoryEntry(
    nextUrl,
    headers,
    html: html,
    baseUrl: baseUrl,
    method: method,
    body: body,
  );
}

/// Coordinates WebView API calls with a controller-owned native WPE renderer.
///
/// Native work is created lazily by the first API that requires WebKit or by a
/// presenting widget. It is not owned by that widget: the controller retains
/// it before first attachment and across later detachments, matching Android
/// WebView and WKWebView controller lifetimes.
class LinuxWebViewController extends PlatformWebViewController {
  /// Creates a controller without immediately allocating native resources.
  // ignore: use_super_parameters
  LinuxWebViewController(PlatformWebViewControllerCreationParams params)
    : this._(params, NativeWebsiteDataStore.shared);

  /// Creates a controller with an injected website-data bridge for tests.
  @visibleForTesting
  LinuxWebViewController.forTesting(
    PlatformWebViewControllerCreationParams params, {
    required NativeWebsiteDataStore websiteDataStore,
  }) : this._(params, websiteDataStore);

  /// Creates a single-use controller around a native related WebView.
  LinuxWebViewController._fromPopup(NativeFrameRenderer renderer)
    : this._(
        const PlatformWebViewControllerCreationParams(),
        NativeWebsiteDataStore.shared,
        popupRenderer: renderer,
        initialTextZoom: renderer.textZoom,
        initialGeolocationEnabled: renderer.geolocationEnabled,
        initialMockCaptureDevicesEnabled: renderer.mockCaptureDevicesEnabled,
        initialJavaScriptCanOpenWindowsAutomatically:
            renderer.javaScriptCanOpenWindowsAutomatically,
        initialJavaScriptCanAccessClipboard:
            renderer.javaScriptCanAccessClipboard,
      );

  // ignore: use_super_parameters
  LinuxWebViewController._(
    PlatformWebViewControllerCreationParams params,
    this._websiteDataStore, {
    NativeFrameRenderer? popupRenderer,
    int initialTextZoom = 100,
    bool initialGeolocationEnabled = true,
    bool initialMockCaptureDevicesEnabled = false,
    bool initialJavaScriptCanOpenWindowsAutomatically = true,
    bool initialJavaScriptCanAccessClipboard = false,
  }) : _renderer = popupRenderer,
       _textZoom = initialTextZoom,
       _textZoomWasSet = initialTextZoom != 100,
       _geolocationEnabled = initialGeolocationEnabled,
       _mockCaptureDevicesEnabled = initialMockCaptureDevicesEnabled,
       _javaScriptCanOpenWindowsAutomatically =
           initialJavaScriptCanOpenWindowsAutomatically,
       _javaScriptCanAccessClipboard = initialJavaScriptCanAccessClipboard,
       _isPopupController = popupRenderer != null,
       super.implementation(params);

  final NativeWebsiteDataStore _websiteDataStore;

  final List<_LinuxHistoryEntry> _history = <_LinuxHistoryEntry>[];
  int _historyIndex = -1;
  String? _currentUrl;
  Map<String, String> _currentRequestHeaders = const <String, String>{};
  String? _lastReportedUrl;
  NativeFrameRenderer? _renderer;
  Future<NativeFrameRenderer>? _rendererCreation;
  Timer? _unattachedPumpTimer;
  final WebViewAttachmentLease _attachmentLease = WebViewAttachmentLease();
  final bool _isPopupController;
  bool _disposed = false;
  LinuxWebViewPopupRequest? _popupRequest;
  LinuxNavigationDelegate? _navigationDelegate;
  int? _lastProgress;
  JavaScriptMode _javaScriptMode = JavaScriptMode.unrestricted;
  String? _userAgent;
  bool _mediaPlaybackRequiresUserGesture = true;
  bool? _mediaPlaybackAllowsInline;
  bool? _webRtcEnabled;
  bool _mockCaptureDevicesEnabled;
  bool? _encryptedMediaEnabled;
  bool _inspectable = false;
  bool _geolocationEnabled;
  bool _javaScriptCanOpenWindowsAutomatically;
  bool _javaScriptCanAccessClipboard;
  bool _zoomEnabled = true;
  int _textZoom;
  bool _textZoomWasSet;
  bool _allowsBackForwardNavigationGestures = false;
  bool _verticalScrollBarEnabled = true;
  bool _horizontalScrollBarEnabled = true;
  WebViewOverScrollMode _overScrollMode =
      WebViewOverScrollMode.ifContentScrolls;
  Color? _backgroundColor;
  bool _eventBridgeInstalled = false;
  bool? _allowFileAccessFromFileUrls;
  bool? _allowUniversalAccessFromFileUrls;
  String? _ignoredInitialUrl;
  void Function(JavaScriptConsoleMessage)? _onConsoleMessage;
  void Function(ScrollPositionChange)? _onScrollPositionChange;
  Future<void> Function(JavaScriptAlertDialogRequest)? _onJavaScriptAlertDialog;
  Future<bool> Function(JavaScriptConfirmDialogRequest)?
  _onJavaScriptConfirmDialog;
  Future<String> Function(JavaScriptTextInputDialogRequest)?
  _onJavaScriptTextInputDialog;
  void Function(PlatformWebViewPermissionRequest)? _onPermissionRequest;
  LinuxWebViewNotificationCallback? _onShowNotification;
  final Map<int, LinuxWebViewNotification> _activeNotifications =
      <int, LinuxWebViewNotification>{};
  Future<List<String>> Function(LinuxFileSelectorParams params)?
  _onShowFileSelector;
  LinuxWebViewDownloadDestinationCallback? _onDownloadDestination;
  LinuxWebViewDownloadEventCallback? _onDownloadEvent;
  LinuxWebViewPopupCallback? _onCreateWindow;
  LinuxWebViewFullscreenChangedCallback? _onFullscreenChanged;
  void Function(bool)? _onCanGoBackChange;
  bool? _lastReportedCanGoBack;
  Offset _lastKnownScrollPosition = Offset.zero;
  Offset? _hiddenScrollPosition;
  bool _rendererSurfaceVisible = false;
  Future<void> _scrollLifecycle = Future<void>.value();
  int _scrollDocumentGeneration = 0;
  final Map<String, JavaScriptChannelParams> _javaScriptChannels =
      <String, JavaScriptChannelParams>{};

  /// The renderer owned by this controller, if native creation has completed.
  ///
  /// This is exposed for the Linux widget implementation and is not part of the
  /// platform-independent `webview_flutter` API.
  NativeFrameRenderer? get renderer => _renderer;

  /// Whether this controller has permanently released its native WebView.
  ///
  /// A controller may be detached and reattached any number of times before
  /// disposal. After [dispose], it cannot create or adopt another renderer.
  bool get isDisposed => _disposed;

  /// Whether the mounted surface should apply touchpad pinch zoom.
  bool get zoomEnabled => _zoomEnabled;

  /// Current text-only zoom percentage retained across attachment.
  int get textZoom => _textZoom;

  /// Whether horizontal touchpad swipes may traverse browser history.
  bool get allowsBackForwardNavigationGestures =>
      _allowsBackForwardNavigationGestures;

  /// Synchronous history availability used at touchpad gesture start.
  bool get canGoBackNow => _renderer?.canGoBack() ?? _historyIndex > 0;

  /// Synchronous forward-history availability used at touchpad gesture start.
  bool get canGoForwardNow =>
      _renderer?.canGoForward() ??
      (_historyIndex >= 0 && _historyIndex < _history.length - 1);

  /// Current vertical scrollbar preference retained across attachment.
  bool get verticalScrollBarEnabled => _verticalScrollBarEnabled;

  /// Current horizontal scrollbar preference retained across attachment.
  bool get horizontalScrollBarEnabled => _horizontalScrollBarEnabled;

  /// Current overscroll preference retained across attachment.
  WebViewOverScrollMode get overScrollMode => _overScrollMode;

  /// Current automatic-media policy retained across attachment.
  bool get mediaPlaybackRequiresUserGesture =>
      _mediaPlaybackRequiresUserGesture;

  /// Explicit inline-media override, or null when WPE's default is retained.
  bool? get mediaPlaybackAllowsInline => _mediaPlaybackAllowsInline;

  /// Explicit WebRTC override, or null when WPE's default is retained.
  bool? get webRtcEnabled => _webRtcEnabled;

  /// Whether deterministic WebKit capture devices are enabled for this view.
  bool get mockCaptureDevicesEnabled => _mockCaptureDevicesEnabled;

  /// Explicit encrypted-media override, or null when WPE's default is retained.
  bool? get encryptedMediaEnabled => _encryptedMediaEnabled;

  /// Explicit adjacent-file access override, or null for load-time behavior.
  bool? get allowFileAccessFromFileUrls => _allowFileAccessFromFileUrls;

  /// Explicit universal file-origin override, or null for WPE's safe default.
  bool? get allowUniversalAccessFromFileUrls =>
      _allowUniversalAccessFromFileUrls;

  /// Whether WebKit developer extras are enabled for this view.
  bool get inspectable => _inspectable;

  /// Whether page geolocation requests are enabled for this WebView.
  bool get geolocationEnabled => _geolocationEnabled;

  /// Whether JavaScript may create related windows without a user gesture.
  bool get javaScriptCanOpenWindowsAutomatically =>
      _javaScriptCanOpenWindowsAutomatically;

  /// Whether page scripts may execute clipboard editing commands.
  bool get javaScriptCanAccessClipboard => _javaScriptCanAccessClipboard;

  /// Returns the existing renderer or creates one for the current engine.
  ///
  /// The caller assumes ownership of the attachment and must eventually pass
  /// the returned instance to [detachRenderer].
  Future<NativeFrameRenderer> attachRenderer(Object attachmentOwner) async {
    _throwIfDisposed();
    // Scroll tracking is an internal lifecycle requirement even when the app
    // does not register the optional federated scroll callback. WPE resets a
    // hidden view's DOM scroll offset, so the controller needs the last visible
    // position in order to preserve Android/WK-style remount semantics.
    _ensureEventBridge();
    _attachmentLease.acquire(attachmentOwner);
    try {
      final renderer = await _ensureRenderer();
      _throwIfDisposed();
      renderer.setVisibility(true);
      _rendererSurfaceVisible = true;
      final hiddenScrollPosition = _hiddenScrollPosition;
      if (hiddenScrollPosition != null) {
        _queueScrollRestoration(renderer, hiddenScrollPosition);
      }
      return renderer;
    } catch (_) {
      // Acquiring a surface is transactional. Creation or visibility failure
      // must not permanently prevent a later attachment attempt.
      _attachmentLease.release(attachmentOwner);
      rethrow;
    }
  }

  /// Returns the controller's renderer, creating it exactly once when needed.
  ///
  /// A controller API and its first widget can race engine discovery. Sharing
  /// one in-flight future prevents duplicate WPE views and textures while still
  /// allowing a failed creation to be retried by a later operation.
  Future<NativeFrameRenderer> _ensureRenderer() async {
    _throwIfDisposed();
    final existing = _renderer;
    if (existing != null) {
      _startUnattachedPump();
      return existing;
    }
    final pending = _rendererCreation;
    if (pending != null) return pending;

    final creation = _createRenderer();
    _rendererCreation = creation;
    try {
      final renderer = await creation;
      _startUnattachedPump();
      return renderer;
    } finally {
      if (identical(_rendererCreation, creation)) _rendererCreation = null;
    }
  }

  /// Allocates and configures one ordinary controller-owned native view.
  Future<NativeFrameRenderer> _createRenderer() async {
    final int engineHandle;
    engineHandle = await EngineContext.instance.getEngineHandle();
    // Disposing while engine discovery is pending must not allow this future
    // to allocate a new WPE view after the controller became terminal.
    _throwIfDisposed();
    // Navigation delegates may complete while engine discovery is awaiting.
    // Snapshot the URL only after that await so the native constructor sees
    // the newest accepted request instead of permanently loading about:blank.
    final currentEntry = _historyIndex >= 0 && _historyIndex < _history.length
        ? _history[_historyIndex]
        : null;
    final currentUrl = _currentUrl;
    final requiresDeferredLoad =
        currentEntry?.html != null ||
        currentEntry?.method == LoadRequestMethod.post ||
        (currentEntry?.headers.isNotEmpty ?? false) ||
        _isLocalFileUrl(currentEntry?.url) ||
        _javaScriptCanAccessClipboard;
    final initialUrl = requiresDeferredLoad
        ? _deferredInitialUrl
        : currentUrl ?? 'about:blank';
    _ignoredInitialUrl = requiresDeferredLoad
        ? _deferredInitialUrl
        : currentUrl == null
        ? 'about:blank'
        : null;
    final renderer = NativeFrameRenderer(
      engineHandle: engineHandle,
      initialUrl: initialUrl,
      javaScriptEnabled: _javaScriptMode == JavaScriptMode.unrestricted,
      javaScriptCanOpenWindowsAutomatically:
          _javaScriptCanOpenWindowsAutomatically,
      javaScriptCanAccessClipboard: _javaScriptCanAccessClipboard,
      userAgent: _userAgent,
      javaScriptChannels: _javaScriptChannels.keys,
      userScripts: _eventBridgeInstalled
          ? const <String>[_eventBridgeScript]
          : const <String>[],
    );
    try {
      final backgroundColor = _backgroundColor;
      if (backgroundColor != null) {
        renderer.setBackgroundColor(backgroundColor.toARGB32());
      }
      _applyPagePresentation(renderer);
      final allowFileAccess =
          _allowFileAccessFromFileUrls ?? _isLocalFileUrl(currentEntry?.url);
      if (allowFileAccess) {
        renderer.setFileAccessEnabled(true);
      } else if (_allowFileAccessFromFileUrls == false) {
        renderer.setFileAccessEnabled(false);
      }
      renderer.setMediaPlaybackRequiresUserGesture(
        _mediaPlaybackRequiresUserGesture,
      );
      if (_mediaPlaybackAllowsInline case final allowed?) {
        renderer.setMediaPlaybackAllowsInline(allowed);
      }
      if (_webRtcEnabled case final enabled?) {
        renderer.setWebRtcEnabled(enabled);
      }
      if (_mockCaptureDevicesEnabled) {
        renderer.setMockCaptureDevicesEnabled(true);
      }
      if (_encryptedMediaEnabled case final enabled?) {
        renderer.setEncryptedMediaEnabled(enabled);
      }
      if (_allowUniversalAccessFromFileUrls case final allowed?) {
        renderer.setUniversalFileAccessEnabled(allowed);
      }
      if (_inspectable) renderer.setInspectable(true);
      if (!_geolocationEnabled) renderer.setGeolocationEnabled(false);
      if (_textZoomWasSet) renderer.setTextZoom(_textZoom);
      _renderer = renderer;
      if (currentEntry?.html case final html?) {
        renderer.loadHtml(html, baseUrl: currentEntry?.baseUrl);
      } else if (requiresDeferredLoad && currentEntry != null) {
        if (currentEntry.method == LoadRequestMethod.post) {
          renderer.navigatePost(
            currentEntry.url,
            headers: currentEntry.headers,
            body: currentEntry.body ?? Uint8List(0),
          );
        } else {
          renderer.navigate(currentEntry.url, headers: currentEntry.headers);
        }
      }
      return renderer;
    } catch (_) {
      if (identical(_renderer, renderer)) _renderer = null;
      renderer.dispose();
      rethrow;
    }
  }

  /// Pumps asynchronous WebKit completions while no Flutter surface exists.
  ///
  /// WPE itself continues on GLib's application loop, but Dart-facing results
  /// are collected by [NativeFrameRenderer.pump]. A weak timer gives APIs such
  /// as JavaScript evaluation the same pre-widget lifecycle as Android and
  /// WKWebView without keeping an otherwise unreachable controller alive.
  void _startUnattachedPump() {
    if (_unattachedPumpTimer != null) return;
    final weakController = WeakReference<LinuxWebViewController>(this);
    late final Timer timer;
    timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final controller = weakController.target;
      if (controller == null) {
        timer.cancel();
        return;
      }
      if (controller._attachmentLease.isAttached) return;
      final renderer = controller._renderer;
      if (renderer == null) return;
      try {
        renderer.pump();
      } catch (error, stackTrace) {
        timer.cancel();
        controller._unattachedPumpTimer = null;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'webview_flutter_linux',
            context: ErrorDescription(
              'while pumping a controller-owned WebView without a widget',
            ),
          ),
        );
      }
    });
    _unattachedPumpTimer = timer;
  }

  /// Detaches [renderer] while retaining the controller-owned native WebView.
  ///
  /// Android and WK controllers keep their native browser independent from the
  /// widget that presents it. Linux follows the same contract: detaching hides
  /// WPE and stops widget pumping, but preserves DOM state, history, scroll,
  /// media, and pending browser work for a later attachment. A stale widget may
  /// safely attempt to release an attachment it no longer owns.
  void detachRenderer(NativeFrameRenderer renderer, Object attachmentOwner) {
    if (!identical(renderer, _renderer)) return;
    if (!_attachmentLease.release(attachmentOwner)) return;
    final scrollPosition = _lastKnownScrollPosition;
    _hiddenScrollPosition = scrollPosition;
    _rendererSurfaceVisible = false;
    renderer.setFocus(false);
    renderer.setVisibility(false);
    _queueScrollRestoration(renderer, scrollPosition);
  }

  /// Applies application lifecycle visibility without discarding page state.
  ///
  /// WPE clears the document scroll offset when an attached view is hidden.
  /// Android WebView and WKWebView retain their page state while their host app
  /// is backgrounded, so Linux snapshots the last visible offset, restores it
  /// after both visibility transitions, and suppresses the synthetic scroll
  /// event emitted by WPE while hidden. The widget remains the attachment owner
  /// throughout this operation.
  void setApplicationVisibility(
    NativeFrameRenderer renderer, {
    required bool visible,
  }) {
    if (_disposed ||
        !identical(renderer, _renderer) ||
        !_attachmentLease.isAttached ||
        _rendererSurfaceVisible == visible) {
      return;
    }
    if (!visible) {
      final scrollPosition = _lastKnownScrollPosition;
      _hiddenScrollPosition = scrollPosition;
      _rendererSurfaceVisible = false;
      renderer.setVisibility(false);
      _queueScrollRestoration(renderer, scrollPosition);
      return;
    }

    renderer.setVisibility(true);
    _rendererSurfaceVisible = true;
    final hiddenScrollPosition = _hiddenScrollPosition;
    if (hiddenScrollPosition != null) {
      _queueScrollRestoration(renderer, hiddenScrollPosition);
    }
  }

  /// Reapplies the logical page offset that WPE clears on visibility changes.
  ///
  /// Detachment is synchronous because Flutter invokes it from widget
  /// disposal, while JavaScript evaluation completes asynchronously through
  /// the renderer pump. Serializing restoration attempts preserves ordering
  /// across a rapid detach/reattach pair. The document generation prevents a
  /// delayed operation from scrolling a newly navigated page.
  void _queueScrollRestoration(NativeFrameRenderer renderer, Offset position) {
    final documentGeneration = _scrollDocumentGeneration;
    _scrollLifecycle = _scrollLifecycle
        .then((_) async {
          if (_disposed ||
              !identical(renderer, _renderer) ||
              documentGeneration != _scrollDocumentGeneration) {
            return;
          }
          await renderer.evaluateJavaScript(
            'window.scrollTo(${position.dx}, ${position.dy});',
          );
          if (_disposed ||
              !identical(renderer, _renderer) ||
              documentGeneration != _scrollDocumentGeneration) {
            return;
          }
          _lastKnownScrollPosition = position;
          if (_attachmentLease.isAttached && _rendererSurfaceVisible) {
            _hiddenScrollPosition = null;
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (_disposed) return;
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'webview_flutter_linux',
              context: ErrorDescription(
                'while preserving WebView scroll across attachment changes',
              ),
            ),
          );
        });
    unawaited(_scrollLifecycle);
  }

  /// Permanently releases this controller's native WebView.
  ///
  /// The presenting [WebViewWidget] must be removed first. Detachment alone is
  /// deliberately non-destructive so a controller can preserve DOM, history,
  /// scroll, and media state across ordinary widget rebuilds. Explicit
  /// disposal is the terminal lifecycle operation for applications that no
  /// longer need that state.
  ///
  /// Popup controllers may also be released through
  /// [LinuxWebViewPopupRequest.dispose]. Repeated calls are harmless. Any later
  /// operation that would create or use a native renderer throws [StateError].
  void dispose() {
    if (_disposed) return;
    if (!_isPopupController && _attachmentLease.isAttached) {
      throw StateError(
        'Remove the WebViewWidget before disposing its Linux controller.',
      );
    }
    _disposed = true;
    _rendererSurfaceVisible = false;
    _attachmentLease.clear();
    _unattachedPumpTimer?.cancel();
    _unattachedPumpTimer = null;
    for (final notification in _activeNotifications.values) {
      notification._didClose();
    }
    _activeNotifications.clear();
    final renderer = _renderer;
    _renderer = null;
    renderer?.dispose();
  }

  /// Releases an adopted popup renderer without requiring a mounted widget.
  void _disposePopup() {
    if (!_isPopupController) return;
    dispose();
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError(
        'This Linux WebView controller has been disposed and cannot be reused.',
      );
    }
  }

  /// Applies lifecycle snapshots drained from the native WebKit event queue.
  ///
  /// This method is public only for coordination with [LinuxWebViewWidget]. It
  /// is not part of the platform-independent `webview_flutter` API.
  void didReceiveNavigationEvents(Iterable<NativeNavigationEvent> events) {
    for (final event in events) {
      final eventUrl = event.url;
      final ignoredInitialUrl = _ignoredInitialUrl;
      if (ignoredInitialUrl != null &&
          (eventUrl.isEmpty || eventUrl == ignoredInitialUrl)) {
        continue;
      }
      if (event.kind == NativeNavigationEventKind.started &&
          eventUrl.isNotEmpty) {
        _ignoredInitialUrl = null;
      }
      if (_isImplicitInitialBlank(eventUrl)) continue;
      switch (event.kind) {
        case NativeNavigationEventKind.started:
          _scrollDocumentGeneration += 1;
          _lastKnownScrollPosition = Offset.zero;
          _hiddenScrollPosition = null;
          if (eventUrl.isNotEmpty) {
            _acceptNativeUrl(eventUrl, addToHistory: eventUrl != _currentUrl);
          }
          _lastProgress = null;
          _emitProgress(0);
          final startedUrl = _eventUrl(eventUrl);
          if (startedUrl != null) {
            _navigationDelegate?.onPageStarted?.call(startedUrl);
          }
        case NativeNavigationEventKind.redirected:
        case NativeNavigationEventKind.committed:
          if (eventUrl.isNotEmpty) {
            _acceptNativeUrl(eventUrl, addToHistory: false);
          }
        case NativeNavigationEventKind.finished:
          if (eventUrl.isNotEmpty) {
            _acceptNativeUrl(eventUrl, addToHistory: false);
          }
          _emitProgress(100);
          final finishedUrl = _eventUrl(eventUrl);
          if (finishedUrl != null) {
            _navigationDelegate?.onPageFinished?.call(finishedUrl);
          }
        case NativeNavigationEventKind.progress:
          _emitProgress(event.progress);
        case NativeNavigationEventKind.resourceError:
          _navigationDelegate?.onWebResourceError?.call(
            WebResourceError(
              errorCode: event.code,
              description: event.detail.isEmpty
                  ? 'WebKit resource load failed.'
                  : event.detail,
              errorType: webResourceErrorTypeForWpeCode(event.code),
              isForMainFrame: event.isMainFrame,
              url: event.url.isEmpty ? null : event.url,
            ),
          );
        case NativeNavigationEventKind.httpError:
          final uri = Uri.tryParse(event.url);
          _navigationDelegate?.onHttpError?.call(
            HttpResponseError(
              request: uri == null ? null : WebResourceRequest(uri: uri),
              response: WebResourceResponse(uri: uri, statusCode: event.code),
            ),
          );
        case NativeNavigationEventKind.webProcessTerminated:
          _navigationDelegate?.onWebResourceError?.call(
            WebResourceError(
              errorCode: event.code,
              description: event.detail.isEmpty
                  ? 'WPE WebKit web process terminated.'
                  : event.detail,
              errorType: WebResourceErrorType.webContentProcessTerminated,
              isForMainFrame: true,
              url: event.url.isEmpty ? null : event.url,
            ),
          );
      }
    }
    _emitCanGoBackChangeIfNeeded();
  }

  /// Dispatches browser-originated channel messages to registered callbacks.
  ///
  /// A message queued just before its channel is removed is ignored. User
  /// callback exceptions are reported through Flutter's error pipeline and do
  /// not stop the native pump shared by rendering and other browser events.
  void didReceiveJavaScriptMessages(
    Iterable<NativeJavaScriptMessage> messages,
  ) {
    for (final message in messages) {
      final callback = _javaScriptChannels[message.channel]?.onMessageReceived;
      if (callback == null) continue;
      try {
        callback(JavaScriptMessage(message: message.message));
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'webview_flutter_linux',
            context: ErrorDescription(
              'while dispatching JavaScript channel ${message.channel}',
            ),
          ),
        );
      }
    }
  }

  /// Starts asynchronous application decisions for WebKit script dialogs.
  ///
  /// Every request has already left the native delivery FIFO. Resolution is
  /// therefore scheduled exactly once, and the native dialog stays retained
  /// while an application callback awaits Flutter UI.
  void didReceiveJavaScriptDialogRequests(
    NativeFrameRenderer renderer,
    Iterable<NativeJavaScriptDialogRequest> requests,
  ) {
    for (final request in requests) {
      unawaited(_resolveJavaScriptDialogRequest(renderer, request));
    }
  }

  /// Invokes the registered federated callback for one native dialog.
  ///
  /// This is visible on the package implementation so callback routing can be
  /// unit tested without constructing a WPE view. Missing callbacks and
  /// callback failures use browser-safe dismissal defaults.
  Future<({bool confirmed, String? promptText})> decideJavaScriptDialogRequest(
    NativeJavaScriptDialogRequest request,
  ) async {
    try {
      switch (request.kind) {
        case NativeJavaScriptDialogKind.alert:
          final callback = _onJavaScriptAlertDialog;
          if (callback != null) {
            await callback(
              JavaScriptAlertDialogRequest(
                message: request.message,
                url: request.url,
              ),
            );
          }
          return (confirmed: true, promptText: null);
        case NativeJavaScriptDialogKind.confirm:
        case NativeJavaScriptDialogKind.beforeUnloadConfirm:
          final callback = _onJavaScriptConfirmDialog;
          if (callback == null) {
            return (confirmed: false, promptText: null);
          }
          final confirmed = await callback(
            JavaScriptConfirmDialogRequest(
              message: request.message,
              url: request.url,
            ),
          );
          return (confirmed: confirmed, promptText: null);
        case NativeJavaScriptDialogKind.prompt:
          final callback = _onJavaScriptTextInputDialog;
          if (callback == null) {
            return (confirmed: false, promptText: null);
          }
          final promptText = await callback(
            JavaScriptTextInputDialogRequest(
              message: request.message,
              url: request.url,
              defaultText: request.defaultText,
            ),
          );
          return (confirmed: true, promptText: promptText);
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription(
            'while handling a ${request.kind.name} JavaScript dialog from '
            '${request.url}',
          ),
        ),
      );
      return (confirmed: false, promptText: null);
    }
  }

  Future<void> _resolveJavaScriptDialogRequest(
    NativeFrameRenderer renderer,
    NativeJavaScriptDialogRequest request,
  ) async {
    final response = await decideJavaScriptDialogRequest(request);
    if (!identical(renderer, _renderer)) return;
    try {
      renderer.resolveJavaScriptDialog(
        request.id,
        confirmed: response.confirmed,
        promptText: response.promptText,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription(
            'while resolving a ${request.kind.name} JavaScript dialog from '
            '${request.url}',
          ),
        ),
      );
    }
  }

  /// Starts asynchronous application decisions for HTML file-input requests.
  ///
  /// Without a registered callback, or when a callback returns an empty list,
  /// the chooser is cancelled. WPE remains retained while Flutter presents its
  /// own picker, so this path never invokes WebKit's fallback GTK dialog.
  void didReceiveFileChooserRequests(
    NativeFrameRenderer renderer,
    Iterable<NativeFileChooserRequest> requests,
  ) {
    for (final request in requests) {
      unawaited(_resolveFileChooserRequest(renderer, request));
    }
  }

  /// Invokes and validates the configured Linux file-selector callback.
  ///
  /// Returned values may be absolute or relative filesystem paths, or `file:`
  /// URIs. They are normalized to existing absolute paths before crossing FFI.
  /// Invalid callback results are reported through [FlutterError] and resolve as
  /// cancellation so the page cannot remain suspended.
  @visibleForTesting
  Future<List<String>> decideFileChooserRequest(
    NativeFileChooserRequest request,
  ) async {
    final callback = _onShowFileSelector;
    if (callback == null) return const <String>[];
    try {
      final selected = await callback(
        LinuxFileSelectorParams(
          mode: request.allowsMultiple
              ? LinuxFileSelectorMode.openMultiple
              : LinuxFileSelectorMode.open,
          acceptedMimeTypes: request.acceptedMimeTypes,
          initialFiles: request.selectedFiles,
        ),
      );
      if (!request.allowsMultiple && selected.length > 1) {
        throw StateError(
          'A single-selection file input received multiple files.',
        );
      }
      final normalized = <String>[];
      for (final value in selected) {
        if (value.isEmpty) {
          throw ArgumentError.value(
            value,
            'selected',
            'File paths cannot be empty.',
          );
        }
        final uri = Uri.tryParse(value);
        final path = uri != null && uri.scheme == 'file'
            ? uri.toFilePath()
            : value;
        if (uri != null && uri.hasScheme && uri.scheme != 'file') {
          throw ArgumentError.value(
            value,
            'selected',
            'Only filesystem paths and file: URIs are supported.',
          );
        }
        final file = File(path).absolute;
        if (!await file.exists()) {
          throw ArgumentError.value(
            value,
            'selected',
            'The selected file does not exist.',
          );
        }
        normalized.add(file.path);
      }
      return List<String>.unmodifiable(normalized);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription('while handling an HTML file chooser'),
        ),
      );
      return const <String>[];
    }
  }

  Future<void> _resolveFileChooserRequest(
    NativeFrameRenderer renderer,
    NativeFileChooserRequest request,
  ) async {
    final selected = await decideFileChooserRequest(request);
    if (!identical(renderer, _renderer)) return;
    try {
      if (selected.isEmpty) {
        renderer.cancelFileChooserRequest(request.id);
      } else {
        renderer.selectFileChooserRequest(request.id, selected);
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription('while resolving an HTML file chooser'),
        ),
      );
      // Native validation leaves a failed selection pending. Best-effort
      // cancellation preserves the exactly-once browser contract.
      if (identical(renderer, _renderer)) {
        try {
          renderer.cancelFileChooserRequest(request.id);
        } catch (_) {
          // Disposal or an already-completed native request needs no follow-up.
        }
      }
    }
  }

  /// Starts destination selection for every browser-initiated download.
  ///
  /// Native WebKit has already paused each request. Missing callbacks,
  /// callback failures, and invalid paths resolve as cancellation so a
  /// headless WebView never writes to an implicit system directory.
  void didReceiveDownloadRequests(
    NativeFrameRenderer renderer,
    Iterable<NativeDownloadRequest> requests,
  ) {
    for (final request in requests) {
      unawaited(_resolveDownloadRequest(renderer, request));
    }
  }

  /// Invokes the configured destination callback and validates its result.
  ///
  /// Only absolute Linux paths and local `file:` URIs are accepted. The parent
  /// directory must already exist; WebKit creates the destination file itself.
  /// Invalid application results are reported and converted to cancellation.
  @visibleForTesting
  Future<LinuxWebViewDownloadDestination?> decideDownloadRequest(
    NativeDownloadRequest request,
  ) async {
    final callback = _onDownloadDestination;
    if (callback == null) return null;
    try {
      final destination = await callback(
        LinuxWebViewDownloadRequest(
          id: request.id,
          url: request.uri,
          suggestedFilename: request.suggestedFilename,
          mimeType: request.mimeType,
          contentLength: request.contentLength,
        ),
      );
      if (destination == null) return null;
      final value = destination.path;
      if (value.isEmpty) {
        throw ArgumentError.value(value, 'path', 'Must not be empty.');
      }
      final uri = Uri.tryParse(value);
      if (uri != null && uri.hasScheme && uri.scheme != 'file') {
        throw ArgumentError.value(
          value,
          'path',
          'Only absolute filesystem paths and file: URIs are supported.',
        );
      }
      final path = uri != null && uri.scheme == 'file'
          ? uri.toFilePath()
          : value;
      if (!path.startsWith('/')) {
        throw ArgumentError.value(
          value,
          'path',
          'The download destination must be absolute.',
        );
      }
      if (await Directory(path).exists()) {
        throw ArgumentError.value(
          value,
          'path',
          'The download destination must name a file, not a directory.',
        );
      }
      final normalized = File(path).absolute;
      if (!await normalized.parent.exists()) {
        throw ArgumentError.value(
          value,
          'path',
          'The destination parent directory does not exist.',
        );
      }
      return LinuxWebViewDownloadDestination(
        normalized.path,
        allowOverwrite: destination.allowOverwrite,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription('while selecting a download destination'),
        ),
      );
      return null;
    }
  }

  Future<void> _resolveDownloadRequest(
    NativeFrameRenderer renderer,
    NativeDownloadRequest request,
  ) async {
    final destination = await decideDownloadRequest(request);
    if (!identical(renderer, _renderer)) return;
    try {
      renderer.resolveDownloadRequest(
        request.id,
        destination: destination?.path,
        allowOverwrite: destination?.allowOverwrite ?? false,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription('while resolving a download request'),
        ),
      );
      if (identical(renderer, _renderer) && destination != null) {
        try {
          renderer.resolveDownloadRequest(request.id, destination: null);
        } catch (_) {
          // Disposal or a completed request needs no additional cancellation.
        }
      }
    }
  }

  /// Dispatches native download lifecycle events to the application callback.
  void didReceiveDownloadEvents(Iterable<NativeDownloadEvent> events) {
    final callback = _onDownloadEvent;
    if (callback == null) return;
    for (final event in events) {
      try {
        callback(
          LinuxWebViewDownloadEvent(
            id: event.id,
            kind: switch (event.kind) {
              NativeDownloadEventKind.createdDestination =>
                LinuxWebViewDownloadEventKind.createdDestination,
              NativeDownloadEventKind.progress =>
                LinuxWebViewDownloadEventKind.progress,
              NativeDownloadEventKind.failed =>
                LinuxWebViewDownloadEventKind.failed,
              NativeDownloadEventKind.finished =>
                LinuxWebViewDownloadEventKind.finished,
            },
            receivedBytes: event.receivedBytes,
            contentLength: event.contentLength,
            destination: event.destination,
            errorCode: event.errorCode,
            errorDescription: event.detail,
          ),
        );
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'webview_flutter_linux',
            context: ErrorDescription(
              'while dispatching a ${event.kind.name} download event',
            ),
          ),
        );
      }
    }
  }

  /// Delivers independently renderable child views created by WebKit.
  ///
  /// Native ownership has already moved out of the opener before this method is
  /// called. Rejected or failing application callbacks therefore dispose the
  /// child explicitly; accepted children remain valid even if the opener is
  /// subsequently removed. Without a callback, a URL-backed request is loaded
  /// in the opener to match the common `webview_flutter` single-window model.
  void didReceivePopupRequests(Iterable<NativePopupRequest> requests) {
    for (final nativeRequest in requests) {
      final popupController = LinuxWebViewController._fromPopup(
        nativeRequest.renderer,
      );
      final request = LinuxWebViewPopupRequest._(
        requestedUrl: nativeRequest.url.isEmpty
            ? null
            : Uri.tryParse(nativeRequest.url),
        platformController: popupController,
      );
      popupController._popupRequest = request;
      if (nativeRequest.renderer.takeWindowCloseRequest()) {
        request._didRequestClose();
      }
      unawaited(_resolvePopupRequest(request));
    }
  }

  Future<void> _resolvePopupRequest(LinuxWebViewPopupRequest request) async {
    final callback = _onCreateWindow;
    if (callback == null) {
      final requestedUrl = request.requestedUrl;
      request.dispose();
      if (requestedUrl == null) return;
      try {
        await loadRequest(LoadRequestParams(uri: requestedUrl));
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'webview_flutter_linux',
            context: ErrorDescription(
              'while opening a related-window request in the current WebView',
            ),
          ),
        );
      }
      return;
    }
    try {
      final accepted = await callback(request);
      if (!accepted) request.dispose();
    } catch (error, stackTrace) {
      request.dispose();
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription(
            'while presenting a WebKit-created popup for '
            '${request.requestedUrl ?? 'an initially blank window'}',
          ),
        ),
      );
    }
  }

  /// Completes the owner-facing close signal for an adopted popup controller.
  void didReceiveWindowCloseRequest() {
    _popupRequest?._didRequestClose();
  }

  /// Notifies the optional application observer of a fullscreen transition.
  void didChangeFullscreen(bool isFullscreen) {
    final callback = _onFullscreenChanged;
    if (callback == null) return;
    try {
      callback(isFullscreen);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription(
            'while reporting an HTML fullscreen transition',
          ),
        ),
      );
    }
  }

  /// Delivers retained WPE permission requests to the federated callback.
  ///
  /// With no callback, access is denied immediately. When a callback exists,
  /// the request remains native-owned until application code calls `grant()`
  /// or `deny()`, allowing a Flutter permission prompt to complete later.
  void didReceivePermissionRequests(
    NativeFrameRenderer renderer,
    Iterable<NativePermissionRequest> requests,
  ) {
    for (final request in requests) {
      final platformRequest = LinuxWebViewPermissionRequest(
        types: decodeNativePermissionResourceTypes(request.resourceTypes),
        onDecision: (allow) async {
          if (!identical(renderer, _renderer)) {
            throw StateError(
              'The WebView was detached before its permission request was '
              'resolved.',
            );
          }
          renderer.resolvePermissionRequest(request.id, allow: allow);
        },
      );
      final callback = _onPermissionRequest;
      if (callback == null) {
        unawaited(_denyPermissionRequest(platformRequest, request));
        continue;
      }
      try {
        callback(platformRequest);
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'webview_flutter_linux',
            context: ErrorDescription(
              'while dispatching a permission request from ${request.url}',
            ),
          ),
        );
        if (!platformRequest.isResolved) {
          unawaited(_denyPermissionRequest(platformRequest, request));
        }
      }
    }
  }

  /// Delivers page-created notifications for Flutter-owned presentation.
  ///
  /// WPE retains each notification after this method returns. With no
  /// callback, or when the callback throws, the notification is closed so a
  /// headless page cannot accumulate invisible native notifications.
  void didReceiveNotifications(
    NativeFrameRenderer renderer,
    Iterable<NativeWebNotification> notifications,
  ) {
    for (final nativeNotification in notifications) {
      final notification = LinuxWebViewNotification(
        id: nativeNotification.id,
        title: nativeNotification.title,
        body: nativeNotification.body,
        tag: nativeNotification.tag,
        url: Uri.tryParse(nativeNotification.url),
        onClick: () async {
          if (!identical(renderer, _renderer)) {
            throw StateError(
              'The WebView was detached before its notification was clicked.',
            );
          }
          renderer.clickNotification(nativeNotification.id);
        },
        onClose: () async {
          if (!identical(renderer, _renderer)) {
            throw StateError(
              'The WebView was detached before its notification was closed.',
            );
          }
          renderer.closeNotification(nativeNotification.id);
        },
      );
      _activeNotifications[nativeNotification.id] = notification;
      unawaited(_presentNotification(notification));
    }
  }

  Future<void> _presentNotification(
    LinuxWebViewNotification notification,
  ) async {
    try {
      final callback = _onShowNotification;
      if (callback == null) {
        await notification.close();
      } else {
        await callback(notification);
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription(
            'while presenting a Web Notification from '
            '${notification.url ?? 'an unknown page'}',
          ),
        ),
      );
      if (!notification.isClosed) {
        try {
          await notification.close();
        } catch (_) {
          // Disposal or page withdrawal already released the native object.
        }
      }
    }
  }

  /// Applies page- and navigation-driven notification withdrawals.
  void didCloseNotifications(Iterable<int> notificationIds) {
    for (final id in notificationIds) {
      _activeNotifications.remove(id)?._didClose();
    }
  }

  /// Delivers retained WPE HTTP-authentication challenges to the delegate.
  ///
  /// Missing callbacks and callback failures cancel the challenge. A callback
  /// may retain [HttpAuthRequest.onProceed] or [HttpAuthRequest.onCancel] while
  /// it presents asynchronous Flutter UI; WPE remains retained until one is
  /// invoked or the WebView is disposed.
  void didReceiveHttpAuthRequests(
    NativeFrameRenderer renderer,
    Iterable<NativeHttpAuthRequest> requests,
  ) {
    for (final nativeRequest in requests) {
      final request = LinuxHttpAuthRequest(
        host: nativeRequest.host,
        realm: nativeRequest.realm,
        onProceed: (credential) {
          if (!identical(renderer, _renderer)) {
            throw StateError(
              'The WebView was detached before its HTTP authentication '
              'request was resolved.',
            );
          }
          renderer.proceedHttpAuthRequest(
            nativeRequest.id,
            username: credential.user,
            password: credential.password,
          );
        },
        onCancel: () {
          if (!identical(renderer, _renderer)) {
            throw StateError(
              'The WebView was detached before its HTTP authentication '
              'request was resolved.',
            );
          }
          renderer.cancelHttpAuthRequest(nativeRequest.id);
        },
      );
      final callback = _navigationDelegate?.onHttpAuthRequest;
      if (callback == null) {
        _cancelHttpAuthRequest(request, nativeRequest);
        continue;
      }
      try {
        callback(request);
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'webview_flutter_linux',
            context: ErrorDescription(
              'while dispatching an HTTP authentication request from '
              '${nativeRequest.host}',
            ),
          ),
        );
        if (!request.isResolved) {
          _cancelHttpAuthRequest(request, nativeRequest);
        }
      }
    }
  }

  /// Delivers retained WPE TLS certificate failures to the delegate.
  ///
  /// With no callback, or if the callback throws before responding, the failed
  /// load remains cancelled. Applications may retain the async decision object
  /// while presenting Flutter UI, matching the federated platform contract.
  void didReceiveSslAuthErrors(
    NativeFrameRenderer renderer,
    Iterable<NativeSslAuthError> errors,
  ) {
    for (final nativeError in errors) {
      final error = LinuxSslAuthError(
        certificate: nativeError.certificateDer.isEmpty
            ? null
            : X509Certificate(data: nativeError.certificateDer),
        description: tlsErrorDescriptionForWpeFlags(nativeError.errorFlags),
        url: nativeError.url,
        errorFlags: nativeError.errorFlags,
        onDecision: (proceed) async {
          if (!identical(renderer, _renderer)) {
            throw StateError(
              'The WebView was detached before its TLS certificate error was '
              'resolved.',
            );
          }
          renderer.resolveSslAuthError(nativeError.id, proceed: proceed);
        },
      );
      final callback = _navigationDelegate?.onSslAuthError;
      if (callback == null) {
        unawaited(_cancelSslAuthError(error, nativeError));
        continue;
      }
      try {
        callback(error);
      } catch (exception, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: exception,
            stack: stackTrace,
            library: 'webview_flutter_linux',
            context: ErrorDescription(
              'while dispatching a TLS certificate error from '
              '${nativeError.url}',
            ),
          ),
        );
        if (!error.isResolved) {
          unawaited(_cancelSslAuthError(error, nativeError));
        }
      }
    }
  }

  Future<void> _cancelSslAuthError(
    LinuxSslAuthError error,
    NativeSslAuthError nativeError,
  ) async {
    try {
      await error.cancel();
    } catch (exception, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription(
            'while cancelling a TLS certificate error from ${nativeError.url}',
          ),
        ),
      );
    }
  }

  void _cancelHttpAuthRequest(
    LinuxHttpAuthRequest request,
    NativeHttpAuthRequest nativeRequest,
  ) {
    try {
      request.onCancel();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription(
            'while cancelling an HTTP authentication request from '
            '${nativeRequest.host}',
          ),
        ),
      );
    }
  }

  Future<void> _denyPermissionRequest(
    LinuxWebViewPermissionRequest platformRequest,
    NativePermissionRequest nativeRequest,
  ) async {
    try {
      await platformRequest.deny();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription(
            'while denying a permission request from ${nativeRequest.url}',
          ),
        ),
      );
    }
  }

  void _ensureEventBridge() {
    if (_eventBridgeInstalled) return;
    final params = JavaScriptChannelParams(
      name: _eventBridgeChannel,
      onMessageReceived: _didReceiveEventBridgeMessage,
    );
    final renderer = _renderer;
    if (renderer != null) {
      renderer.addJavaScriptChannel(_eventBridgeChannel);
      renderer.addUserScript(_eventBridgeScript);
    }
    _javaScriptChannels[_eventBridgeChannel] = params;
    _eventBridgeInstalled = true;
  }

  void _didReceiveEventBridgeMessage(JavaScriptMessage message) {
    final Object? decoded;
    try {
      decoded = jsonDecode(message.message);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['type']) {
      case 'console':
        final text = decoded['message'];
        final level = decoded['level'];
        if (text is! String || level is! String) return;
        _onConsoleMessage?.call(
          JavaScriptConsoleMessage(
            level: switch (level) {
              'error' => JavaScriptLogLevel.error,
              'warning' => JavaScriptLogLevel.warning,
              'debug' => JavaScriptLogLevel.debug,
              'info' => JavaScriptLogLevel.info,
              _ => JavaScriptLogLevel.log,
            },
            message: text,
          ),
        );
      case 'scroll':
        final x = decoded['x'];
        final y = decoded['y'];
        if (x is num && y is num) {
          final position = Offset(x.toDouble(), y.toDouble());
          if (_attachmentLease.isAttached && _rendererSurfaceVisible) {
            _lastKnownScrollPosition = position;
          }
          _onScrollPositionChange?.call(
            ScrollPositionChange(position.dx, position.dy),
          );
        }
    }
  }

  /// Starts asynchronous delegate decisions for page-originated navigations.
  ///
  /// Native WebKit policy objects remain retained by [renderer] until each
  /// callback completes. Requests are already removed from the delivery FIFO,
  /// so later pump ticks cannot invoke the delegate twice.
  void didReceiveNavigationPolicyRequests(
    NativeFrameRenderer renderer,
    Iterable<NativeNavigationPolicyRequest> requests,
  ) {
    for (final request in requests) {
      unawaited(_resolveNavigationPolicyRequest(renderer, request));
    }
  }

  Future<void> _resolveNavigationPolicyRequest(
    NativeFrameRenderer renderer,
    NativeNavigationPolicyRequest request,
  ) async {
    var allow = true;
    final callback = _navigationDelegate?.onNavigationRequest;
    if (callback != null) {
      try {
        final decision = await callback(
          NavigationRequest(url: request.url, isMainFrame: request.isMainFrame),
        );
        allow = decision == NavigationDecision.navigate;
      } catch (error, stackTrace) {
        allow = false;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'webview_flutter_linux',
            context: ErrorDescription(
              'while deciding navigation to ${request.url}',
            ),
          ),
        );
      }
    }
    if (!identical(renderer, _renderer)) return;
    try {
      renderer.resolveNavigationPolicy(request.id, allow: allow);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription(
            'while resolving navigation to ${request.url}',
          ),
        ),
      );
    }
  }

  bool _isImplicitInitialBlank(String eventUrl) =>
      _lastReportedUrl == null &&
      _currentUrl != 'about:blank' &&
      (eventUrl.isEmpty || eventUrl == 'about:blank');

  String? _eventUrl(String eventUrl) =>
      eventUrl.isNotEmpty ? eventUrl : _currentUrl;

  void _emitProgress(int progress) {
    final value = progress.clamp(0, 100);
    if (_lastProgress == value) return;
    _lastProgress = value;
    _navigationDelegate?.onProgress?.call(value);
  }

  void _emitCanGoBackChangeIfNeeded() {
    final canGoBack = canGoBackNow;
    if (_lastReportedCanGoBack == canGoBack) return;
    _lastReportedCanGoBack = canGoBack;
    _onCanGoBackChange?.call(canGoBack);
  }

  void _acceptNativeUrl(String url, {required bool addToHistory}) {
    _currentUrl = url;
    if (addToHistory) {
      if (_historyIndex + 1 < _history.length) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      final entry = _LinuxHistoryEntry(url, const <String, String>{});
      _history.add(entry);
      _historyIndex = _history.length - 1;
      _currentRequestHeaders = entry.headers;
    } else if (_historyIndex >= 0) {
      final entry = _history[_historyIndex].withUrl(url);
      _history[_historyIndex] = entry;
      _currentRequestHeaders = entry.headers;
    } else {
      final entry = _LinuxHistoryEntry(url, const <String, String>{});
      _history.add(entry);
      _historyIndex = 0;
      _currentRequestHeaders = entry.headers;
    }
    if (url != _lastReportedUrl) {
      _lastReportedUrl = url;
      _navigationDelegate?.onUrlChange?.call(UrlChange(url: url));
    }
  }

  @override
  Future<void> loadFile(String absoluteFilePath) async {
    final file = File(absoluteFilePath);
    if (!file.existsSync()) {
      throw ArgumentError.value(
        absoluteFilePath,
        'absoluteFilePath',
        'The file does not exist.',
      );
    }
    await _loadUrl(Uri.file(file.absolute.path).toString());
  }

  @override
  Future<void> loadFlutterAsset(String key) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    if (!manifest.listAssets().contains(key)) {
      throw ArgumentError.value(
        key,
        'key',
        'The Flutter asset is not declared.',
      );
    }
    final assetUri = resolveLinuxFlutterAssetUri(
      executablePath: Platform.resolvedExecutable,
      assetKey: key,
    );
    if (!File.fromUri(assetUri).existsSync()) {
      throw StateError(
        'Flutter declared asset `$key`, but it was not found in the Linux '
        'application bundle at ${assetUri.toFilePath()}.',
      );
    }
    await _loadUrl(assetUri.toString());
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    final normalizedBaseUrl = baseUrl == null || baseUrl.isEmpty
        ? null
        : baseUrl;
    await _loadEntry(
      _LinuxHistoryEntry(
        normalizedBaseUrl ?? 'about:blank',
        const <String, String>{},
        html: html,
        baseUrl: normalizedBaseUrl,
      ),
    );
  }

  /// Loads a GET or POST request with optional main-resource HTTP headers.
  ///
  /// POST is represented by WebKit's native form-history state so the binary
  /// body participates in the browser's ordinary network and history stack;
  /// headers are attached to the corresponding native main-resource request.
  /// WPE has no public API for representing a GET navigation body, so a body
  /// supplied with GET is accepted but ignored, matching Android WebView.
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    if (!params.uri.hasScheme) {
      throw ArgumentError('LoadRequestParams.uri must have a scheme.');
    }
    _validateRequestHeaders(params.headers);
    if (params.method == LoadRequestMethod.post) {
      await _loadEntry(
        _LinuxHistoryEntry(
          params.uri.toString(),
          params.headers,
          method: LoadRequestMethod.post,
          body: params.body ?? Uint8List(0),
        ),
      );
      return;
    }
    await _loadUrl(params.uri.toString(), headers: params.headers);
  }

  void _validateRequestHeaders(Map<String, String> headers) {
    if (headers.length > 1024) {
      throw ArgumentError.value(
        headers.length,
        'headers',
        'At most 1024 request headers are supported.',
      );
    }
    for (final MapEntry(key: name, value: value) in headers.entries) {
      if (!_httpHeaderNamePattern.hasMatch(name)) {
        throw ArgumentError.value(name, 'headers', 'Invalid HTTP header name.');
      }
      if (value.contains('\r') || value.contains('\n')) {
        throw ArgumentError.value(
          value,
          'headers',
          'HTTP header values must not contain CR or LF.',
        );
      }
    }
  }

  Future<void> _loadUrl(
    String url, {
    bool addToHistory = true,
    Map<String, String> headers = const <String, String>{},
  }) =>
      _loadEntry(_LinuxHistoryEntry(url, headers), addToHistory: addToHistory);

  Future<void> _loadEntry(
    _LinuxHistoryEntry entry, {
    bool addToHistory = true,
  }) async {
    _throwIfDisposed();
    final callback = _navigationDelegate?.onNavigationRequest;
    if (callback != null) {
      final decision = await callback(
        NavigationRequest(url: entry.url, isMainFrame: true),
      );
      if (decision == NavigationDecision.prevent) return;
      _throwIfDisposed();
    }

    _currentUrl = entry.url;
    _currentRequestHeaders = entry.headers;
    if (addToHistory) {
      if (_historyIndex + 1 < _history.length) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(entry);
      _historyIndex = _history.length - 1;
    }
    _emitCanGoBackChangeIfNeeded();
    final renderer = _renderer;
    if (renderer == null) return;
    if (_isLocalFileUrl(entry.url) && _allowFileAccessFromFileUrls == null) {
      renderer.setFileAccessEnabled(true);
    }
    final html = entry.html;
    if (html != null) {
      renderer.loadHtml(html, baseUrl: entry.baseUrl);
    } else if (entry.method == LoadRequestMethod.post) {
      renderer.navigatePost(
        entry.url,
        headers: entry.headers,
        body: entry.body ?? Uint8List(0),
      );
    } else {
      renderer.navigate(entry.url, headers: entry.headers);
    }
  }

  bool _isLocalFileUrl(String? url) =>
      url != null && Uri.tryParse(url)?.scheme == 'file';

  @override
  Future<String?> currentUrl() async {
    final nativeUrl = _renderer?.currentUrl;
    if (nativeUrl != null) _currentUrl = nativeUrl;
    return nativeUrl ?? _currentUrl;
  }

  @override
  Future<bool> canGoBack() async {
    final renderer = _renderer;
    return renderer?.canGoBack() ?? _historyIndex > 0;
  }

  @override
  Future<bool> canGoForward() async {
    final renderer = _renderer;
    return renderer?.canGoForward() ??
        (_historyIndex >= 0 && _historyIndex + 1 < _history.length);
  }

  @override
  Future<void> goBack() async {
    final renderer = _renderer;
    if (renderer != null) {
      if (renderer.canGoBack()) renderer.goBack();
      return;
    }
    if (!await canGoBack()) return;
    _historyIndex -= 1;
    final entry = _history[_historyIndex];
    await _loadEntry(entry, addToHistory: false);
  }

  @override
  Future<void> goForward() async {
    final renderer = _renderer;
    if (renderer != null) {
      if (renderer.canGoForward()) renderer.goForward();
      return;
    }
    if (!await canGoForward()) return;
    _historyIndex += 1;
    final entry = _history[_historyIndex];
    await _loadEntry(entry, addToHistory: false);
  }

  @override
  Future<void> reload() async {
    final renderer = _renderer;
    if (renderer != null) {
      renderer.reload();
      return;
    }
    if (_historyIndex >= 0 && _historyIndex < _history.length) {
      await _loadEntry(_history[_historyIndex], addToHistory: false);
    } else if (_currentUrl case final url?) {
      await _loadUrl(url, headers: _currentRequestHeaders, addToHistory: false);
    }
  }

  /// Intentionally terminates the mounted WebKit content process in tests.
  ///
  /// The resulting failure is reported through `onWebResourceError` with
  /// [WebResourceErrorType.webContentProcessTerminated]. The controller does
  /// not reload automatically; tests may call [reload] to verify that WebKit
  /// creates a replacement process. Production applications must not use this
  /// diagnostic hook.
  @visibleForTesting
  void terminateWebProcessForTesting() {
    _requireRenderer().terminateWebProcessForTesting();
  }

  @override
  Future<void> clearCache() =>
      _websiteDataStore.clear((1 << 0) | (1 << 1) | (1 << 2) | (1 << 11));

  @override
  Future<void> clearLocalStorage() => _websiteDataStore.clear(1 << 4);

  NativeFrameRenderer _requireRenderer() {
    _throwIfDisposed();
    final renderer = _renderer;
    if (renderer == null) {
      throw StateError('The WebViewWidget must be mounted first.');
    }
    return renderer;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    if (handler is! LinuxNavigationDelegate) {
      throw ArgumentError.value(
        handler,
        'handler',
        'Expected a LinuxNavigationDelegate.',
      );
    }
    _navigationDelegate = handler;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    try {
      await _evaluateJavaScript(javaScript);
    } on PlatformException catch (error) {
      // Side-effecting WebKit APIs can succeed but return a native object that
      // JavaScriptCore cannot marshal. The void federated API intentionally
      // ignores only that result-shape error; script exceptions still surface.
      if (error.code != 'javascript_result_unsupported') rethrow;
    }
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    final name = javaScriptChannelParams.name;
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
    if (_javaScriptChannels.containsKey(name)) {
      throw ArgumentError('A JavaScriptChannel with name `$name` exists.');
    }
    _renderer?.addJavaScriptChannel(name);
    _javaScriptChannels[name] = javaScriptChannelParams;
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    if (!_javaScriptChannels.containsKey(javaScriptChannelName)) return;
    _renderer?.removeJavaScriptChannel(javaScriptChannelName);
    _javaScriptChannels.remove(javaScriptChannelName);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    return normalizeJavaScriptResult(await _evaluateJavaScript(javaScript));
  }

  @override
  Future<String?> getTitle() async => (await _ensureRenderer()).title;

  @override
  Future<void> scrollTo(int x, int y) async {
    await runJavaScript('window.scrollTo($x, $y);');
    _lastKnownScrollPosition = Offset(x.toDouble(), y.toDouble());
  }

  @override
  Future<void> scrollBy(int x, int y) async {
    await runJavaScript('window.scrollBy($x, $y);');
    _lastKnownScrollPosition += Offset(x.toDouble(), y.toDouble());
  }

  @override
  Future<Offset> getScrollPosition() async {
    final position = decodeJavaScriptScrollPosition(
      await runJavaScriptReturningResult('[window.scrollX, window.scrollY]'),
    );
    _lastKnownScrollPosition = position;
    return position;
  }

  @override
  Future<void> setVerticalScrollBarEnabled(bool enabled) async {
    _verticalScrollBarEnabled = enabled;
    final renderer = _renderer;
    if (renderer != null) _applyPagePresentation(renderer);
  }

  @override
  Future<void> setHorizontalScrollBarEnabled(bool enabled) async {
    _horizontalScrollBarEnabled = enabled;
    final renderer = _renderer;
    if (renderer != null) _applyPagePresentation(renderer);
  }

  @override
  bool supportsSetScrollBarsEnabled() => true;

  @override
  Future<void> setOverScrollMode(WebViewOverScrollMode mode) async {
    _overScrollMode = mode;
    final renderer = _renderer;
    if (renderer != null) _applyPagePresentation(renderer);
  }

  void _applyPagePresentation(NativeFrameRenderer renderer) {
    renderer.setPagePresentation(
      verticalScrollBarEnabled: _verticalScrollBarEnabled,
      horizontalScrollBarEnabled: _horizontalScrollBarEnabled,
      overscrollMode: switch (_overScrollMode) {
        WebViewOverScrollMode.always => 0,
        WebViewOverScrollMode.ifContentScrolls => 1,
        WebViewOverScrollMode.never => 2,
      },
    );
  }

  Future<Object?> _evaluateJavaScript(String javaScript) async {
    if (!_attachmentLease.isAttached || !_rendererSurfaceVisible) {
      await _scrollLifecycle;
    }
    return (await _ensureRenderer()).evaluateJavaScript(javaScript);
  }

  @override
  Future<void> enableZoom(bool enabled) async {
    _zoomEnabled = enabled;
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    _backgroundColor = color;
    _renderer?.setBackgroundColor(color.toARGB32());
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    _javaScriptMode = javaScriptMode;
    _renderer?.setJavaScriptEnabled(
      javaScriptMode == JavaScriptMode.unrestricted,
    );
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {
    _userAgent = userAgent;
    _renderer?.setUserAgent(userAgent);
  }

  /// Sets whether media may load or play without a user gesture.
  ///
  /// This is the Linux equivalent of Android's platform-specific media
  /// playback policy. WPE defaults to allowing automatic playback.
  Future<void> setMediaPlaybackRequiresUserGesture(bool require) async {
    _mediaPlaybackRequiresUserGesture = require;
    _renderer?.setMediaPlaybackRequiresUserGesture(require);
  }

  /// Sets whether media elements may play inline inside the WebView.
  ///
  /// This maps to WPE's fullscreen-versus-inline media policy and is
  /// independent from [setMediaPlaybackRequiresUserGesture]. Calling it before
  /// widget attachment retains the preference for native view creation.
  Future<void> setMediaPlaybackAllowsInline(bool allow) async {
    _mediaPlaybackAllowsInline = allow;
    _renderer?.setMediaPlaybackAllowsInline(allow);
  }

  /// Enables or disables WebRTC for subsequently executed page content.
  ///
  /// Enabling WebRTC also enables MediaStream in WPE. Camera, microphone, and
  /// display-capture requests still require an explicit permission decision.
  Future<void> setWebRtcEnabled(bool enabled) async {
    _webRtcEnabled = enabled;
    _renderer?.setWebRtcEnabled(enabled);
  }

  /// Enables deterministic camera and microphone devices for automation.
  ///
  /// This does not bypass [setOnPlatformPermissionRequest]: pages must still
  /// receive an explicit grant. Production applications should leave this
  /// disabled and use the host's real capture devices.
  Future<void> setMockCaptureDevicesEnabled(bool enabled) async {
    _mockCaptureDevicesEnabled = enabled;
    _renderer?.setMockCaptureDevicesEnabled(enabled);
  }

  /// Enables or disables the Encrypted Media Extensions API.
  ///
  /// The host WPE and GStreamer installation must still provide a compatible
  /// content-decryption module; this switch cannot install one.
  Future<void> setEncryptedMediaEnabled(bool enabled) async {
    _encryptedMediaEnabled = enabled;
    _renderer?.setEncryptedMediaEnabled(enabled);
  }

  /// Controls whether a `file:` document may request other local files.
  ///
  /// When never called, [loadFile] and [loadFlutterAsset] enable adjacent local
  /// resources automatically. An explicit false keeps cross-file requests
  /// disabled even for later local navigations.
  Future<void> setAllowFileAccessFromFileUrls(bool allow) async {
    _allowFileAccessFromFileUrls = allow;
    _renderer?.setFileAccessEnabled(allow);
  }

  /// Controls whether `file:` documents may access resources from any origin.
  ///
  /// This relaxes WebKit's same-origin protections and therefore remains at
  /// WPE's disabled default until the application explicitly opts in.
  Future<void> setAllowUniversalAccessFromFileUrls(bool allow) async {
    _allowUniversalAccessFromFileUrls = allow;
    _renderer?.setUniversalFileAccessEnabled(allow);
  }

  /// Reads effective optional-feature settings from the native WPE view.
  ///
  /// Host support is reported separately from the setting value because WPE
  /// exposes stable setters even when a distribution compiled WebRTC or
  /// encrypted media out of its browser runtime.
  Future<LinuxWebViewCapabilityState> getCapabilityState() async =>
      LinuxWebViewCapabilityState.fromFlags(
        (await _ensureRenderer()).capabilityFlags,
      );

  /// Enables or disables WPE WebKit developer extras for this view.
  ///
  /// The setting is disabled by default and retained when called before the
  /// WebView widget attaches, matching the lifecycle of WKWebView's
  /// platform-specific `setInspectable` API.
  Future<void> setInspectable(bool inspectable) async {
    _inspectable = inspectable;
    _renderer?.setInspectable(inspectable);
  }

  /// Controls whether page scripts may execute cut, copy, and paste commands.
  ///
  /// WPE disables script-driven clipboard access by default. Enabling this
  /// setting allows `document.execCommand` clipboard operations while the
  /// existing Linux clipboard bridge continues to own desktop synchronization.
  /// Applications should enable it only for content they trust.
  Future<void> setJavaScriptCanAccessClipboard(bool enabled) async {
    _javaScriptCanAccessClipboard = enabled;
    _renderer?.setJavaScriptCanAccessClipboard(enabled);
  }

  /// Enables or disables the Geolocation API for this WebView.
  ///
  /// The default is true, matching Android. Permission is still required when
  /// enabled: requests continue through [setOnPlatformPermissionRequest] and a
  /// position provider must be installed through
  /// [LinuxWebViewGeolocationManager]. Disabling takes precedence over an
  /// application permission grant and rejects requests already awaiting one.
  Future<void> setGeolocationEnabled(bool enabled) async {
    _geolocationEnabled = enabled;
    _renderer?.setGeolocationEnabled(enabled);
  }

  /// Controls whether JavaScript may open a related window without a gesture.
  ///
  /// The default is true, matching the Android implementation's WebView
  /// initialization. The popup still reaches [setOnCreateWindow], so Flutter
  /// retains ownership of whether the related view is presented or disposed.
  Future<void> setJavaScriptCanOpenWindowsAutomatically(bool enabled) async {
    _javaScriptCanOpenWindowsAutomatically = enabled;
    _renderer?.setJavaScriptCanOpenWindowsAutomatically(enabled);
  }

  /// Sets text-only zoom as a percentage, matching Android's controller API.
  ///
  /// The default is 100. WPE accepts values from 10 through 1000. A non-default
  /// value makes the native zoom factor affect text and text-bearing form
  /// controls without scaling other page content. Setting 100 restores the
  /// ordinary full-page zoom mode used by touchpad pinch gestures.
  Future<void> setTextZoom(int textZoom) async {
    if (textZoom < 10 || textZoom > 1000) {
      throw ArgumentError.value(
        textZoom,
        'textZoom',
        'Must be between 10 and 1000 percent.',
      );
    }
    _textZoom = textZoom;
    _textZoomWasSet = true;
    _renderer?.setTextZoom(textZoom);
  }

  /// Enables two-axis touchpad recognition for back/forward history swipes.
  ///
  /// This is the Linux counterpart of WKWebView's
  /// `setAllowsBackForwardNavigationGestures`. It is opt-in because claiming a
  /// horizontal pan changes how pages with horizontally scrollable content
  /// behave. Vertical pans and unavailable history directions remain ordinary
  /// page scroll gestures.
  Future<void> setAllowsBackForwardNavigationGestures(bool enabled) async {
    _allowsBackForwardNavigationGestures = enabled;
  }

  /// Sets a listener that is called whenever browser history changes whether
  /// the current page can navigate backward.
  ///
  /// This mirrors WebKit's platform-specific `setOnCanGoBackChange` API. The
  /// listener observes controller requests made before the widget mounts as
  /// well as page-initiated and gesture-driven changes reported by WPE.
  Future<void> setOnCanGoBackChange(
    void Function(bool canGoBack) onCanGoBackChange,
  ) async {
    _onCanGoBackChange = onCanGoBackChange;
    _lastReportedCanGoBack = canGoBackNow;
  }

  @override
  Future<String?> getUserAgent() async =>
      (await _ensureRenderer()).getUserAgent();

  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) async {
    _onConsoleMessage = onConsoleMessage;
    _ensureEventBridge();
  }

  @override
  Future<void> setOnScrollPositionChange(
    void Function(ScrollPositionChange scrollPositionChange)?
    onScrollPositionChange,
  ) async {
    _onScrollPositionChange = onScrollPositionChange;
    if (onScrollPositionChange != null) _ensureEventBridge();
  }

  @override
  Future<void> setOnJavaScriptAlertDialog(
    Future<void> Function(JavaScriptAlertDialogRequest request)
    onJavaScriptAlertDialog,
  ) async {
    _onJavaScriptAlertDialog = onJavaScriptAlertDialog;
  }

  @override
  Future<void> setOnJavaScriptConfirmDialog(
    Future<bool> Function(JavaScriptConfirmDialogRequest request)
    onJavaScriptConfirmDialog,
  ) async {
    _onJavaScriptConfirmDialog = onJavaScriptConfirmDialog;
  }

  @override
  Future<void> setOnJavaScriptTextInputDialog(
    Future<String> Function(JavaScriptTextInputDialogRequest request)
    onJavaScriptTextInputDialog,
  ) async {
    _onJavaScriptTextInputDialog = onJavaScriptTextInputDialog;
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {
    _onPermissionRequest = onPermissionRequest;
  }

  /// Registers application-owned presentation for page Web Notifications.
  ///
  /// The callback receives notification metadata and may retain the object
  /// while system or in-app UI is visible. Call [LinuxWebViewNotification.click]
  /// for user activation and [LinuxWebViewNotification.close] when that UI is
  /// dismissed. Passing null restores the safe default of immediate closure.
  Future<void> setOnShowNotification(
    LinuxWebViewNotificationCallback? onShowNotification,
  ) async {
    _onShowNotification = onShowNotification;
  }

  /// Registers a Flutter-owned picker for HTML `<input type="file">` controls.
  ///
  /// The callback must return existing filesystem paths or `file:` URIs. An
  /// empty list cancels selection. Setting [onShowFileSelector] to null restores
  /// the safe default of cancelling requests without opening a native dialog.
  Future<void> setOnShowFileSelector(
    Future<List<String>> Function(LinuxFileSelectorParams params)?
    onShowFileSelector,
  ) async {
    _onShowFileSelector = onShowFileSelector;
  }

  /// Registers the Flutter-owned destination picker for native downloads.
  ///
  /// Set null to restore the safe default of cancelling downloads. The
  /// callback may await UI and must return an absolute local destination.
  Future<void> setOnDownloadDestination(
    LinuxWebViewDownloadDestinationCallback? onDownloadDestination,
  ) async {
    _onDownloadDestination = onDownloadDestination;
  }

  /// Registers an observer for native download lifecycle transitions.
  ///
  /// Set null to stop receiving events. Downloads continue independently of
  /// whether an observer is installed.
  Future<void> setOnDownloadEvent(
    LinuxWebViewDownloadEventCallback? onDownloadEvent,
  ) async {
    _onDownloadEvent = onDownloadEvent;
  }

  /// Registers the Flutter-owned presenter for `target="_blank"` and
  /// `window.open()` children.
  ///
  /// The callback receives a related WebView only after WebKit emits
  /// `ready-to-show`. Return true after retaining or presenting the request;
  /// false rejects and disposes it. Passing null restores the common
  /// single-window behavior, where URL-backed requests navigate this WebView.
  Future<void> setOnCreateWindow(
    LinuxWebViewPopupCallback? onCreateWindow,
  ) async {
    _onCreateWindow = onCreateWindow;
  }

  /// Registers an observer for HTML fullscreen enter and leave transitions.
  ///
  /// The Linux widget provides a default root-overlay presentation regardless
  /// of whether an observer is installed.
  Future<void> setOnFullscreenChanged(
    LinuxWebViewFullscreenChangedCallback? onFullscreenChanged,
  ) async {
    _onFullscreenChanged = onFullscreenChanged;
  }
}
