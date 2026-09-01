// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'native_frame_bindings.dart';
import 'webview_accessibility.dart';
import 'webview_cursor.dart';
import 'webview_text_input.dart';

/// Normalized logical geometry supplied to WPE's scaled render surface.
final class WpeSurfaceGeometry {
  /// Creates one validated WPE viewport description.
  const WpeSurfaceGeometry({
    required this.logicalWidth,
    required this.logicalHeight,
    required this.scale,
  });

  /// Integer viewport width exposed to web content.
  final int logicalWidth;

  /// Integer viewport height exposed to web content.
  final int logicalHeight;

  /// Flutter display scale forwarded as the browser device scale factor.
  final double scale;

  /// Expected upper bound for the physical render-buffer width.
  int get physicalWidth => (logicalWidth * scale).ceil();

  /// Expected upper bound for the physical render-buffer height.
  int get physicalHeight => (logicalHeight * scale).ceil();
}

/// Validates and bounds Flutter geometry without conflating logical and
/// physical pixels.
WpeSurfaceGeometry normalizeWpeSurfaceGeometry({
  required double logicalWidth,
  required double logicalHeight,
  required double deviceScaleFactor,
}) {
  if (!logicalWidth.isFinite || logicalWidth < 0) {
    throw ArgumentError.value(logicalWidth, 'logicalWidth');
  }
  if (!logicalHeight.isFinite || logicalHeight < 0) {
    throw ArgumentError.value(logicalHeight, 'logicalHeight');
  }
  if (!deviceScaleFactor.isFinite || deviceScaleFactor <= 0) {
    throw ArgumentError.value(deviceScaleFactor, 'deviceScaleFactor');
  }
  final scale = deviceScaleFactor.clamp(0.5, 4).toDouble();
  final maxLogicalDimension = (16384 / scale).floor().clamp(1, 16384).toInt();
  return WpeSurfaceGeometry(
    logicalWidth: logicalWidth.ceil().clamp(1, maxLogicalDimension).toInt(),
    logicalHeight: logicalHeight.ceil().clamp(1, maxLogicalDimension).toInt(),
    scale: scale,
  );
}

/// Describes one entry in a browser-owned context menu.
final class BrowserContextMenuItem {
  /// Creates an immutable snapshot of a native menu entry.
  const BrowserContextMenuItem({
    required this.index,
    required this.title,
    required this.isSeparator,
    required this.isEnabled,
    required this.stockAction,
  });

  /// The index required to activate this item through the native bridge.
  final int index;

  /// The display label with native mnemonic markers removed.
  final String title;

  /// Whether this entry should render as a visual separator.
  final bool isSeparator;

  /// Whether the browser permits this item to be activated.
  final bool isEnabled;

  /// WebKit's locale-independent `WebKitContextMenuAction` value.
  final int stockAction;
}

/// A point-in-time copy of the context menu exposed by WPE.
final class NativeBrowserContextMenu {
  /// Creates a menu positioned in logical Flutter coordinates.
  const NativeBrowserContextMenu({required this.position, required this.items});

  /// The menu origin relative to the WebView surface.
  final Offset position;

  /// The ordered native menu entries.
  final List<BrowserContextMenuItem> items;
}

/// One entry in a browser-owned HTML `<select>` popup.
final class BrowserOptionMenuItem {
  /// Creates an immutable copy of one WebKit option entry.
  const BrowserOptionMenuItem({
    required this.index,
    required this.label,
    required this.tooltip,
    required this.isGroupLabel,
    required this.isGroupChild,
    required this.isEnabled,
    required this.isSelected,
  });

  /// Snapshot index required to activate this entry through the native bridge.
  final int index;

  /// Text displayed for this option or option-group heading.
  final String label;

  /// Optional explanatory text supplied by the page.
  final String? tooltip;

  /// Whether this entry is an `<optgroup>` heading rather than an option.
  final bool isGroupLabel;

  /// Whether this option should be visually indented below a group heading.
  final bool isGroupChild;

  /// Whether WebKit permits the option to be activated.
  final bool isEnabled;

  /// Whether this option is the element's current value.
  final bool isSelected;
}

/// A retained HTML option menu positioned over its WebView element.
final class NativeBrowserOptionMenu {
  /// Creates an immutable menu snapshot.
  NativeBrowserOptionMenu({
    required this.bounds,
    required List<BrowserOptionMenuItem> items,
  }) : items = List<BrowserOptionMenuItem>.unmodifiable(items);

  /// Logical Flutter bounds of the originating `<select>` element.
  final Rect bounds;

  /// Ordered group headings and options supplied by WebKit.
  final List<BrowserOptionMenuItem> items;
}

/// The lifecycle transition represented by a native WebKit signal.
enum NativeNavigationEventKind {
  /// WebKit accepted a new main-frame load.
  started(1),

  /// The provisional main-frame load followed a redirect.
  redirected(2),

  /// Response content began arriving for the main frame.
  committed(3),

  /// WebKit completed the load and all of its resources.
  finished(4),

  /// WebKit updated its estimated load percentage.
  progress(5),

  /// The main resource failed before completing its load.
  resourceError(6),

  /// A response returned an HTTP status in the 400 through 599 range.
  httpError(7),

  /// WebKit's web-content process exited abnormally.
  webProcessTerminated(8);

  const NativeNavigationEventKind(this.wireValue);

  /// Integer value shared with the Rust C ABI.
  final int wireValue;

  /// Resolves a Rust wire value, returning `null` for a newer unknown event.
  static NativeNavigationEventKind? fromWireValue(int value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

/// An owned lifecycle event copied from the native WebKit queue.
final class NativeNavigationEvent {
  /// Creates one immutable event snapshot.
  const NativeNavigationEvent({
    required this.kind,
    required this.url,
    required this.progress,
    this.code = 0,
    this.detail = '',
    this.isMainFrame = true,
  });

  /// Native lifecycle transition.
  final NativeNavigationEventKind kind;

  /// Main-frame URL reported by WebKit, or an empty string when unavailable.
  final String url;

  /// Estimated load progress clamped to the inclusive range 0 through 100.
  final int progress;

  /// Native resource error code or HTTP response status code.
  final int code;

  /// Human-readable native error description, when available.
  final String detail;

  /// Whether WebKit associated this event with the main frame.
  final bool isMainFrame;
}

/// An owned message copied from a WebKit JavaScript channel.
final class NativeJavaScriptMessage {
  /// Creates an immutable browser-originated message.
  const NativeJavaScriptMessage({required this.channel, required this.message});

  /// Name of the channel whose `postMessage` function was invoked.
  final String channel;

  /// JavaScript value converted to the federated channel string contract.
  final String message;
}

/// A WebKit navigation action awaiting the Dart delegate's decision.
final class NativeNavigationPolicyRequest {
  /// Creates an immutable request identified by [id].
  const NativeNavigationPolicyRequest({
    required this.id,
    required this.url,
    required this.isMainFrame,
  });

  /// Opaque native request ID used to resolve the retained decision.
  final int id;

  /// Destination URL proposed by WebKit.
  final String url;

  /// Whether the navigation targets the main page frame.
  final bool isMainFrame;
}

/// A WebKit-related child view transferred out of its opener's native queue.
///
/// [renderer] already owns a registered Flutter texture and must either be
/// attached to a popup controller or disposed. The requested URL can be empty
/// for script-created windows that navigate only after creation.
final class NativePopupRequest {
  /// Creates an owned popup snapshot.
  const NativePopupRequest({required this.url, required this.renderer});

  /// URL copied from the navigation action that requested the child.
  final String url;

  /// Independently owned renderer for the related child WebView.
  final NativeFrameRenderer renderer;
}

/// JavaScript dialog type reported by WPE.
enum NativeJavaScriptDialogKind {
  /// `window.alert`.
  alert(0),

  /// `window.confirm`.
  confirm(1),

  /// `window.prompt`.
  prompt(2),

  /// A page's `beforeunload` confirmation.
  beforeUnloadConfirm(3);

  const NativeJavaScriptDialogKind(this.wireValue);

  /// Integer value shared with WebKit's dialog enum.
  final int wireValue;

  /// Decodes one WebKit enum value.
  static NativeJavaScriptDialogKind? fromWireValue(int value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

/// A retained JavaScript dialog awaiting the application's async response.
final class NativeJavaScriptDialogRequest {
  /// Creates an immutable copy of one WPE dialog request.
  const NativeJavaScriptDialogRequest({
    required this.id,
    required this.kind,
    required this.message,
    required this.url,
    required this.defaultText,
  });

  /// Native request ID required for resolution.
  final int id;

  /// Alert, confirm, prompt, or before-unload confirmation.
  final NativeJavaScriptDialogKind kind;

  /// Dialog message supplied by the page.
  final String message;

  /// Main-frame URL that raised the dialog.
  final String url;

  /// Initial prompt text, or null for non-prompt dialogs and absent defaults.
  final String? defaultText;
}

/// A retained HTML file-input request awaiting a Flutter file picker.
final class NativeFileChooserRequest {
  /// Creates an owned copy of one WPE file chooser request.
  NativeFileChooserRequest({
    required this.id,
    required this.allowsMultiple,
    required List<String> acceptedMimeTypes,
    required List<String> selectedFiles,
  }) : acceptedMimeTypes = List<String>.unmodifiable(acceptedMimeTypes),
       selectedFiles = List<String>.unmodifiable(selectedFiles);

  /// Native request ID required to select files or cancel.
  final int id;

  /// Whether the HTML input accepts more than one file.
  final bool allowsMultiple;

  /// MIME types copied from the input's `accept` attribute.
  final List<String> acceptedMimeTypes;

  /// Files retained from a previous chooser invocation, when provided by WPE.
  final List<String> selectedFiles;
}

/// A native WPE download paused while Flutter selects its destination.
final class NativeDownloadRequest {
  /// Creates an immutable copy of response metadata for one download.
  const NativeDownloadRequest({
    required this.id,
    required this.uri,
    required this.suggestedFilename,
    required this.mimeType,
    required this.contentLength,
  });

  /// Stable per-view identifier used for exactly-once resolution.
  final int id;

  /// Original resource URI copied from WebKit's request.
  final String uri;

  /// Server-suggested filename, or an empty string when unavailable.
  final String suggestedFilename;

  /// Response MIME type, or null when unavailable.
  final String? mimeType;

  /// Expected response bytes, or null when the server omitted the size.
  final int? contentLength;
}

/// Native lifecycle states emitted by a WPE download.
enum NativeDownloadEventKind {
  /// WebKit successfully created the selected destination file.
  createdDestination(1),

  /// More response bytes were written to the destination.
  progress(2),

  /// WebKit failed or cancelled the download.
  failed(3),

  /// The download ended, after [failed] when it did not succeed.
  finished(4);

  const NativeDownloadEventKind(this.wireValue);

  /// Integer value shared with the Rust ABI.
  final int wireValue;

  /// Decodes one stable Rust ABI value.
  static NativeDownloadEventKind? fromWireValue(int value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

/// An owned lifecycle snapshot copied from a native WPE download.
final class NativeDownloadEvent {
  /// Creates one immutable download transition.
  const NativeDownloadEvent({
    required this.id,
    required this.kind,
    required this.receivedBytes,
    required this.contentLength,
    required this.errorCode,
    required this.destination,
    required this.detail,
  });

  /// Stable identifier shared with [NativeDownloadRequest.id].
  final int id;

  /// Created, progress, failed, or finished transition.
  final NativeDownloadEventKind kind;

  /// Total bytes written when WebKit emitted this transition.
  final int receivedBytes;

  /// Expected response bytes, or null when unknown.
  final int? contentLength;

  /// WPE download error code for [NativeDownloadEventKind.failed].
  final int errorCode;

  /// Absolute destination selected for the download, when available.
  final String? destination;

  /// Human-readable native failure detail, when available.
  final String? detail;
}

/// A retained WebKit permission request awaiting a host decision.
final class NativePermissionRequest {
  /// Creates an immutable copy of one native permission request.
  const NativePermissionRequest({
    required this.id,
    required this.resourceTypes,
    required this.url,
  });

  /// Native request ID required for grant or denial.
  final int id;

  /// Bitmask describing every WPE resource requested together.
  final int resourceTypes;

  /// URL of the page requesting access.
  final String url;
}

/// An owned copy of a page-created Web Notification.
final class NativeWebNotification {
  /// Creates immutable notification metadata copied from WPE.
  const NativeWebNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.tag,
    required this.url,
  });

  /// Handle-scoped ID used for click and close operations.
  final int id;

  /// Page-supplied notification title.
  final String title;

  /// Page-supplied notification body.
  final String body;

  /// Optional replacement-group tag supplied by the page.
  final String? tag;

  /// Main-frame URL active when WebKit created the notification.
  final String url;
}

/// A retained WebKit HTTP-authentication challenge awaiting credentials.
final class NativeHttpAuthRequest {
  /// Creates an immutable copy of one native authentication challenge.
  const NativeHttpAuthRequest({
    required this.id,
    required this.host,
    required this.realm,
  });

  /// Native request ID required to proceed or cancel.
  final int id;

  /// Host that issued the authentication challenge.
  final String host;

  /// Authentication realm, or null when the server omitted it.
  final String? realm;
}

/// A retained main-load TLS certificate failure awaiting a host decision.
final class NativeSslAuthError {
  /// Creates an immutable copy of one native TLS failure.
  const NativeSslAuthError({
    required this.id,
    required this.url,
    required this.errorFlags,
    required this.certificateDer,
  });

  /// Native request ID required to proceed or cancel.
  final int id;

  /// HTTPS URL whose certificate validation failed.
  final String url;

  /// GLib `GTlsCertificateFlags` bitmask describing validation failures.
  final int errorFlags;

  /// DER bytes for the leaf certificate, or an empty list if unavailable.
  final Uint8List certificateDer;
}

/// Decodes the wire representation returned by JavaScriptCore.
///
/// Status zero carries UTF-8 JSON. Statuses one and two represent JavaScript
/// `null` and `undefined`; negative statuses carry an error message.
Object? decodeJavaScriptResult(int status, String payload) {
  switch (status) {
    case 0:
      return jsonDecode(payload) as Object?;
    case 1:
    case 2:
      return null;
    case 3:
      throw PlatformException(
        code: 'javascript_result_unsupported',
        message: payload.isEmpty
            ? 'JavaScript returned an unsupported result type.'
            : payload,
        details: <String, Object?>{'nativeStatus': status},
      );
    default:
      throw PlatformException(
        code: 'javascript_error',
        message: payload.isEmpty ? 'JavaScript evaluation failed.' : payload,
        details: <String, Object?>{'nativeStatus': status},
      );
  }
}

/// Touch contact transition encoded by the Dart-to-Rust input ABI.
enum NativeTouchEventType {
  /// A new contact touched the surface.
  down,

  /// An existing contact moved across the surface.
  move,

  /// An existing contact left the surface normally.
  up,

  /// The platform cancelled an existing contact stream.
  cancel,
}

/// Owns one native browser view and its Flutter external texture.
///
/// Each instance receives an opaque handle at creation and passes that handle
/// to every Rust ABI call. Controllers retain the renderer across temporary
/// widget detachments. [dispose] provides deterministic teardown for explicitly
/// owned popup views, while a native finalizer safely releases an otherwise
/// unreachable controller-owned renderer on GLib's platform thread.
final class NativeFrameRenderer implements Finalizable {
  /// Creates a WPE view attached to the Flutter engine identified by
  /// [engineHandle].
  ///
  /// Native resources created before a constructor failure are released before
  /// the error is rethrown.
  NativeFrameRenderer({
    required int engineHandle,
    String initialUrl = 'about:blank',
    bool javaScriptEnabled = true,
    bool javaScriptCanOpenWindowsAutomatically = true,
    bool javaScriptCanAccessClipboard = false,
    String? userAgent,
    Iterable<String> javaScriptChannels = const <String>[],
    Iterable<String> userScripts = const <String>[],
  }) : apiVersion = webviewFlutterLinuxApiVersion() {
    if (apiVersion != expectedApiVersion) {
      throw StateError(
        'Incompatible webview_flutter_linux native ABI: expected '
        '$expectedApiVersion, received $apiVersion.',
      );
    }
    var createdHandle = 0;
    final outputHandle = calloc<Uint64>();
    final nativeUrl = initialUrl.toNativeUtf8();
    final nativeUserAgent = userAgent?.toNativeUtf8();
    try {
      _checkStatus(
        'native WebView creation',
        webviewFlutterLinuxViewCreate(
          engineHandle,
          nativeUrl.cast(),
          javaScriptEnabled ? 1 : 0,
          javaScriptCanOpenWindowsAutomatically ? 1 : 0,
          javaScriptCanAccessClipboard ? 1 : 0,
          nativeUserAgent?.cast() ?? nullptr,
          outputHandle,
        ),
      );
      createdHandle = outputHandle.value;
      if (createdHandle == 0) {
        throw StateError('Native WebView creation returned an invalid handle.');
      }
      handle = createdHandle;
      for (final channel in javaScriptChannels) {
        addJavaScriptChannel(channel);
      }
      for (final source in userScripts) {
        addUserScript(source);
      }
      _lastClipboardChangeCount = webviewFlutterLinuxWpeClipboardChangeCount(
        handle,
      );
      setVisibility(true);
    } catch (_) {
      if (createdHandle != 0) {
        webviewFlutterLinuxViewDispose(createdHandle);
      }
      rethrow;
    } finally {
      calloc.free(nativeUrl);
      if (nativeUserAgent != null) calloc.free(nativeUserAgent);
      calloc.free(outputHandle);
    }
    _attachFinalizer();
  }

  /// Adopts a related WebView handle transferred from an opener.
  ///
  /// The native `create` handler has already registered the child's Irondash
  /// texture and completed WPE construction. This constructor validates that
  /// transfer and assumes exactly the same disposal responsibility as ordinary
  /// controller-created renderers. A failed adoption releases the transferred
  /// handle before reporting the error.
  NativeFrameRenderer.adopt({required int nativeHandle})
    : apiVersion = webviewFlutterLinuxApiVersion() {
    if (apiVersion != expectedApiVersion) {
      // This path is defensive: obtaining a popup handle itself requires the
      // current ABI. Avoid calling a potentially incompatible dispose symbol.
      throw StateError(
        'Incompatible webview_flutter_linux native ABI: expected '
        '$expectedApiVersion, received $apiVersion.',
      );
    }
    if (nativeHandle <= 0) {
      throw ArgumentError.value(
        nativeHandle,
        'nativeHandle',
        'Must identify a transferred native WebView.',
      );
    }
    handle = nativeHandle;
    try {
      if (textureId <= 0) {
        throw StateError(
          'Transferred native WebView $nativeHandle has no Flutter texture.',
        );
      }
      _lastClipboardChangeCount = webviewFlutterLinuxWpeClipboardChangeCount(
        handle,
      );
      setVisibility(true);
    } catch (_) {
      webviewFlutterLinuxViewDispose(nativeHandle);
      _disposed = true;
      rethrow;
    }
    _attachFinalizer();
  }

  /// The ABI version reported by the loaded native library.
  final int apiVersion;

  /// Native ABI required by this Dart implementation.
  static const int expectedApiVersion = 29;

  static final NativeFinalizer _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
      webviewFlutterLinuxViewDisposeFinalizer,
    ),
  );

  /// The opaque identifier for this renderer's native view.
  late final int handle;
  int _lastRequestedTextureGeneration = -1;
  int _lastPaintCount = 0;
  int _lastContextMenuGeneration = 0;
  int _lastOptionMenuGeneration = 0;
  int _lastInputMethodGeneration = 0;
  int _lastCursorGeneration = -1;
  int _lastClipboardChangeCount = -1;
  int _pendingClipboardExportRequest = 0;
  int _nextJavaScriptRequestId = 1;
  final Map<int, Completer<Object?>> _pendingJavaScript =
      <int, Completer<Object?>>{};
  double _deviceScaleFactor = 1;
  bool _disposed = false;

  void _attachFinalizer() {
    _finalizer.attach(this, Pointer<Void>.fromAddress(handle), detach: this);
  }

  /// The external texture identifier registered with the Flutter engine.
  int get textureId => webviewFlutterLinuxTextureId(handle);

  /// The current native texture width in physical pixels.
  int get textureWidth => webviewFlutterLinuxTextureWidth(handle);

  /// The current native texture height in physical pixels.
  int get textureHeight => webviewFlutterLinuxTextureHeight(handle);

  /// Flutter scale forwarded to WPE and used for custom cursor pixels.
  double get deviceScaleFactor => _deviceScaleFactor;

  /// Copies a changed browser cursor, returning `null` while its generation is
  /// unchanged.
  NativeBrowserCursor? takeCursor() {
    _ensureAlive();
    final generation = webviewFlutterLinuxWpeCursorGeneration(handle);
    if (generation == 0 || generation == _lastCursorGeneration) return null;

    final cursor = switch (webviewFlutterLinuxWpeCursorKind(handle)) {
      1 => NativeNamedBrowserCursor(
        generation: generation,
        name: _copyNamedCursor(),
      ),
      2 => _copyCustomCursor(generation),
      final kind => throw StateError(
        'WPE returned unsupported cursor kind $kind for generation '
        '$generation.',
      ),
    };
    _lastCursorGeneration = generation;
    return cursor;
  }

  String _copyNamedCursor() {
    final length = webviewFlutterLinuxWpeCursorNameLength(handle);
    if (length <= 0 || length > 128) {
      throw StateError('WPE returned invalid cursor name length $length.');
    }
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeCursorCopyName(
        handle,
        destination,
        length,
      );
      if (copied != length) {
        throw StateError(
          'WPE cursor name copy returned $copied of $length bytes.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  NativeCustomBrowserCursor _copyCustomCursor(int generation) {
    final width = webviewFlutterLinuxWpeCursorWidth(handle);
    final height = webviewFlutterLinuxWpeCursorHeight(handle);
    final hotspotX = webviewFlutterLinuxWpeCursorHotspotX(handle);
    final hotspotY = webviewFlutterLinuxWpeCursorHotspotY(handle);
    final length = webviewFlutterLinuxWpeCursorPixelsLength(handle);
    final expectedLength = width * height * 4;
    if (width <= 0 ||
        height <= 0 ||
        hotspotX >= width ||
        hotspotY >= height ||
        length != expectedLength ||
        length > 4 * 1024 * 1024) {
      throw StateError(
        'WPE returned invalid custom cursor dimensions: '
        '${width}x$height, hotspot ($hotspotX, $hotspotY), $length bytes.',
      );
    }
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeCursorCopyPixels(
        handle,
        destination,
        length,
      );
      if (copied != length) {
        throw StateError(
          'WPE custom cursor copy returned $copied of $length bytes.',
        );
      }
      return NativeCustomBrowserCursor(
        generation: generation,
        width: width,
        height: height,
        hotspotX: hotspotX,
        hotspotY: hotspotY,
        pixels: Uint8List.fromList(destination.asTypedList(copied)),
      );
    } finally {
      calloc.free(destination);
    }
  }

  /// The number of frames the WPE view has painted.
  int get paintCount => webviewFlutterLinuxWpePaintCount(handle);

  /// Advances native work and requests a Flutter frame when content changed.
  ///
  /// Returns whether a texture generation or WPE paint counter changed during
  /// this call.
  bool pump() {
    _ensureAlive();
    _checkStatus('WPE event pump', webviewFlutterLinuxWpePump(handle));
    _drainJavaScriptResults();
    final generation = webviewFlutterLinuxTextureGeneration(handle);
    final nextPaintCount = paintCount;
    if (generation != _lastRequestedTextureGeneration ||
        nextPaintCount != _lastPaintCount) {
      _checkStatus(
        'Flutter texture frame request',
        webviewFlutterLinuxTextureRequestFrame(handle),
      );
      _lastRequestedTextureGeneration = generation;
      _lastPaintCount = nextPaintCount;
      return true;
    }
    return false;
  }

  /// Whether WebKit's native session history has a previous item.
  bool canGoBack() {
    _ensureAlive();
    final status = webviewFlutterLinuxWpeCanGoBack(handle);
    if (status < 0) {
      throw StateError('Native canGoBack query failed with status $status.');
    }
    return status != 0;
  }

  /// Whether WebKit's native session history has a following item.
  bool canGoForward() {
    _ensureAlive();
    final status = webviewFlutterLinuxWpeCanGoForward(handle);
    if (status < 0) {
      throw StateError('Native canGoForward query failed with status $status.');
    }
    return status != 0;
  }

  /// Traverses to the previous item without reconstructing its request.
  void goBack() {
    _ensureAlive();
    _checkStatus(
      'native history back traversal',
      webviewFlutterLinuxWpeGoBack(handle),
    );
  }

  /// Traverses to the following item without reconstructing its request.
  void goForward() {
    _ensureAlive();
    _checkStatus(
      'native history forward traversal',
      webviewFlutterLinuxWpeGoForward(handle),
    );
  }

  /// Reloads WebKit's current history item and original request.
  void reload() {
    _ensureAlive();
    _checkStatus('native page reload', webviewFlutterLinuxWpeReload(handle));
  }

  /// Navigates the native view to [url] with optional main-request headers.
  void navigate(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) {
    _ensureAlive();
    if (headers.length > 1024) {
      throw ArgumentError.value(
        headers.length,
        'headers',
        'At most 1024 request headers are supported.',
      );
    }
    final nativeUrl = url.toNativeUtf8();
    final nativeNames = <Pointer<Utf8>>[];
    final nativeValues = <Pointer<Utf8>>[];
    final namePointers = calloc<Pointer<Char>>(headers.length);
    final valuePointers = calloc<Pointer<Char>>(headers.length);
    try {
      var index = 0;
      for (final MapEntry(key: name, value: value) in headers.entries) {
        final nativeName = name.toNativeUtf8();
        final nativeValue = value.toNativeUtf8();
        nativeNames.add(nativeName);
        nativeValues.add(nativeValue);
        namePointers[index] = nativeName.cast();
        valuePointers[index] = nativeValue.cast();
        index += 1;
      }
      _checkStatus(
        'navigation',
        headers.isEmpty
            ? webviewFlutterLinuxWpeNavigate(handle, nativeUrl.cast())
            : webviewFlutterLinuxWpeNavigateWithHeaders(
                handle,
                nativeUrl.cast(),
                namePointers,
                valuePointers,
                headers.length,
              ),
      );
    } finally {
      calloc.free(nativeUrl);
      for (final name in nativeNames) {
        calloc.free(name);
      }
      for (final value in nativeValues) {
        calloc.free(value);
      }
      calloc.free(namePointers);
      calloc.free(valuePointers);
    }
  }

  /// Navigates the native view with POST and an arbitrary binary [body].
  ///
  /// The native bridge constructs a WebKit form-history item rather than
  /// issuing the request through a second HTTP client. Cookies, redirects,
  /// cache behavior, security origin, response rendering, and history
  /// therefore remain owned by WebKit. The bridge attaches [headers] when WPE
  /// exposes the corresponding native main-resource request, preserving both
  /// arbitrary binary bodies and caller-supplied POST headers.
  void navigatePost(
    String url, {
    Map<String, String> headers = const <String, String>{},
    required Uint8List body,
  }) {
    _ensureAlive();
    if (headers.length > 1024) {
      throw ArgumentError.value(
        headers.length,
        'headers',
        'At most 1024 request headers are supported.',
      );
    }
    final nativeUrl = url.toNativeUtf8();
    final nativeNames = <Pointer<Utf8>>[];
    final nativeValues = <Pointer<Utf8>>[];
    final namePointers = calloc<Pointer<Char>>(headers.length);
    final valuePointers = calloc<Pointer<Char>>(headers.length);
    final Pointer<Uint8> nativeBody = body.isEmpty
        ? nullptr
        : calloc<Uint8>(body.length);
    try {
      var index = 0;
      for (final MapEntry(key: name, value: value) in headers.entries) {
        final nativeName = name.toNativeUtf8();
        final nativeValue = value.toNativeUtf8();
        nativeNames.add(nativeName);
        nativeValues.add(nativeValue);
        namePointers[index] = nativeName.cast();
        valuePointers[index] = nativeValue.cast();
        index += 1;
      }
      if (body.isNotEmpty) {
        nativeBody.asTypedList(body.length).setAll(0, body);
      }
      _checkStatus(
        'POST navigation',
        webviewFlutterLinuxWpeNavigatePost(
          handle,
          nativeUrl.cast(),
          namePointers,
          valuePointers,
          headers.length,
          nativeBody,
          body.length,
        ),
      );
    } finally {
      calloc.free(nativeUrl);
      for (final name in nativeNames) {
        calloc.free(name);
      }
      for (final value in nativeValues) {
        calloc.free(value);
      }
      calloc.free(namePointers);
      calloc.free(valuePointers);
      if (nativeBody != nullptr) calloc.free(nativeBody);
    }
  }

  /// Loads [html] as a document using WebKit's native base-URI semantics.
  ///
  /// A null [baseUrl] gives the document an `about:blank` base. Unlike the
  /// former `data:` URL implementation, WebKit receives the source directly
  /// and resolves relative document resources against [baseUrl].
  void loadHtml(String html, {String? baseUrl}) {
    _ensureAlive();
    final nativeHtml = html.toNativeUtf8();
    final nativeBaseUrl = baseUrl?.toNativeUtf8();
    try {
      _checkStatus(
        'HTML document load',
        webviewFlutterLinuxWpeLoadHtml(
          handle,
          nativeHtml.cast(),
          nativeBaseUrl?.cast() ?? nullptr,
        ),
      );
    } finally {
      calloc.free(nativeHtml);
      if (nativeBaseUrl != null) calloc.free(nativeBaseUrl);
    }
  }

  /// Evaluates [script] in the current page and completes with its Dart value.
  ///
  /// WebKit evaluates asynchronously. The native completion callback stores a
  /// request-ID-tagged result, and [pump] resolves the matching completer after
  /// copying that result back across FFI.
  Future<Object?> evaluateJavaScript(String script) async {
    _ensureAlive();
    final requestId = _allocateRequestId();
    final completer = Completer<Object?>();
    _pendingJavaScript[requestId] = completer;
    final nativeScript = script.toNativeUtf8();
    try {
      _checkStatus(
        'JavaScript evaluation',
        webviewFlutterLinuxWpeEvaluateJavaScript(
          handle,
          requestId,
          nativeScript.cast(),
        ),
      );
    } catch (_) {
      _pendingJavaScript.remove(requestId);
      rethrow;
    } finally {
      calloc.free(nativeScript);
    }
    return completer.future;
  }

  int _allocateRequestId() {
    final requestId = _nextJavaScriptRequestId;
    _nextJavaScriptRequestId = requestId == 0x7fffffffffffffff
        ? 1
        : requestId + 1;
    return requestId;
  }

  /// Installs a named `Channel.postMessage(value)` bridge in WebKit.
  void addJavaScriptChannel(String channel) {
    _ensureAlive();
    final nativeChannel = channel.toNativeUtf8();
    try {
      _checkStatus(
        'JavaScript channel installation',
        webviewFlutterLinuxWpeAddJavaScriptChannel(
          handle,
          nativeChannel.cast(),
        ),
      );
    } finally {
      calloc.free(nativeChannel);
    }
  }

  /// Removes a named JavaScript channel from current and future documents.
  void removeJavaScriptChannel(String channel) {
    _ensureAlive();
    final nativeChannel = channel.toNativeUtf8();
    try {
      _checkStatus(
        'JavaScript channel removal',
        webviewFlutterLinuxWpeRemoveJavaScriptChannel(
          handle,
          nativeChannel.cast(),
        ),
      );
    } finally {
      calloc.free(nativeChannel);
    }
  }

  /// Installs [source] at document start and executes it in the current page.
  void addUserScript(String source) {
    _ensureAlive();
    final nativeSource = source.toNativeUtf8();
    try {
      _checkStatus(
        'document-start user script installation',
        webviewFlutterLinuxWpeAddUserScript(handle, nativeSource.cast()),
      );
    } finally {
      calloc.free(nativeSource);
    }
  }

  /// Applies application-controlled scrollbar and overscroll presentation.
  void setPagePresentation({
    required bool verticalScrollBarEnabled,
    required bool horizontalScrollBarEnabled,
    required int overscrollMode,
  }) {
    _ensureAlive();
    _checkStatus(
      'page presentation update',
      webviewFlutterLinuxWpeSetPagePresentation(
        handle,
        verticalScrollBarEnabled ? 1 : 0,
        horizontalScrollBarEnabled ? 1 : 0,
        overscrollMode,
      ),
    );
  }

  /// Resolves every JavaScript completion currently queued by WebKit.
  void _drainJavaScriptResults() {
    final pending = webviewFlutterLinuxWpeJavaScriptResultCount(handle);
    for (var index = 0; index < pending; index += 1) {
      final requestId = webviewFlutterLinuxWpeJavaScriptResultRequestId(handle);
      final status = webviewFlutterLinuxWpeJavaScriptResultStatus(handle);
      try {
        final payload = _copyJavaScriptResultPayload();
        final completer = _pendingJavaScript.remove(requestId);
        if (completer != null) {
          try {
            completer.complete(decodeJavaScriptResult(status, payload));
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        }
      } catch (error, stackTrace) {
        _pendingJavaScript.remove(requestId)?.completeError(error, stackTrace);
      } finally {
        _checkStatus(
          'JavaScript result acknowledgement',
          webviewFlutterLinuxWpeJavaScriptResultPop(handle),
        );
      }
    }
  }

  String _copyJavaScriptResultPayload() {
    final length = webviewFlutterLinuxWpeJavaScriptResultPayloadLength(handle);
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeJavaScriptResultCopyPayload(
        handle,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE JavaScript result read failed with status $copied.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  /// Drains browser-to-Dart channel messages in their native arrival order.
  List<NativeJavaScriptMessage> takeJavaScriptMessages() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeJavaScriptMessageCount(handle);
    final messages = <NativeJavaScriptMessage>[];
    for (var index = 0; index < pending; index += 1) {
      try {
        final channel = _copyJavaScriptMessageText(
          webviewFlutterLinuxWpeJavaScriptMessageChannelLength(handle),
          webviewFlutterLinuxWpeJavaScriptMessageCopyChannel,
          'channel name',
        );
        final message = _copyJavaScriptMessageText(
          webviewFlutterLinuxWpeJavaScriptMessagePayloadLength(handle),
          webviewFlutterLinuxWpeJavaScriptMessageCopyPayload,
          'payload',
        );
        messages.add(
          NativeJavaScriptMessage(channel: channel, message: message),
        );
      } finally {
        _checkStatus(
          'JavaScript message acknowledgement',
          webviewFlutterLinuxWpeJavaScriptMessagePop(handle),
        );
      }
    }
    return messages;
  }

  /// Delivers each new WebKit navigation action to Dart exactly once.
  List<NativeNavigationPolicyRequest> takeNavigationPolicyRequests() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeNavigationPolicyRequestCount(handle);
    final requests = <NativeNavigationPolicyRequest>[];
    for (var index = 0; index < pending; index += 1) {
      try {
        final id = webviewFlutterLinuxWpeNavigationPolicyRequestId(handle);
        final isMainFrame =
            webviewFlutterLinuxWpeNavigationPolicyRequestIsMainFrame(handle) !=
            0;
        final length = webviewFlutterLinuxWpeNavigationPolicyRequestUrlLength(
          handle,
        );
        var url = '';
        if (length > 0) {
          final destination = calloc<Uint8>(length);
          try {
            final copied = webviewFlutterLinuxWpeNavigationPolicyRequestCopyUrl(
              handle,
              destination,
              length,
            );
            if (copied < 0) {
              throw StateError(
                'WPE navigation policy URL read failed with status $copied.',
              );
            }
            url = utf8.decode(
              destination.asTypedList(copied),
              allowMalformed: true,
            );
          } finally {
            calloc.free(destination);
          }
        }
        requests.add(
          NativeNavigationPolicyRequest(
            id: id,
            url: url,
            isMainFrame: isMainFrame,
          ),
        );
      } finally {
        _checkStatus(
          'navigation policy request delivery',
          webviewFlutterLinuxWpeNavigationPolicyRequestTake(handle),
        );
      }
    }
    return requests;
  }

  /// Allows or prevents a previously delivered WebKit navigation action.
  void resolveNavigationPolicy(int requestId, {required bool allow}) {
    _ensureAlive();
    _checkStatus(
      'navigation policy resolution',
      webviewFlutterLinuxWpeNavigationPolicyResolve(
        handle,
        requestId,
        allow ? 1 : 0,
      ),
    );
  }

  /// Delivers each new WebKit JavaScript dialog to Dart exactly once.
  ///
  /// WebKit retains the underlying dialog after it moves from the native FIFO
  /// into the delivered set. Call [resolveJavaScriptDialog] for every returned
  /// request so the page's JavaScript execution can continue.
  List<NativeJavaScriptDialogRequest> takeJavaScriptDialogRequests() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeScriptDialogRequestCount(handle);
    final requests = <NativeJavaScriptDialogRequest>[];
    for (var index = 0; index < pending; index += 1) {
      final id = webviewFlutterLinuxWpeScriptDialogRequestId(handle);
      final kind = NativeJavaScriptDialogKind.fromWireValue(
        webviewFlutterLinuxWpeScriptDialogRequestKind(handle),
      );
      final message = _copyJavaScriptDialogField(0, 'message');
      final url = _copyJavaScriptDialogField(1, 'URL');
      final hasDefaultText =
          webviewFlutterLinuxWpeScriptDialogRequestHasDefaultText(handle) != 0;
      final defaultText = hasDefaultText
          ? _copyJavaScriptDialogField(2, 'default text')
          : null;

      _checkStatus(
        'JavaScript dialog request delivery',
        webviewFlutterLinuxWpeScriptDialogRequestTake(handle),
      );
      if (kind == null) {
        // A newer native enum must never leave page execution suspended. The
        // conservative fallback dismisses it after removing it from the FIFO.
        _checkStatus(
          'unknown JavaScript dialog dismissal',
          webviewFlutterLinuxWpeScriptDialogResolve(handle, id, 0, nullptr),
        );
        continue;
      }
      requests.add(
        NativeJavaScriptDialogRequest(
          id: id,
          kind: kind,
          message: message,
          url: url,
          defaultText: defaultText,
        ),
      );
    }
    return requests;
  }

  /// Completes a JavaScript dialog previously returned to Dart.
  ///
  /// [confirmed] is used by confirm and before-unload dialogs. For prompts,
  /// [promptText] is the accepted value and `null` cancels the prompt. Alerts
  /// ignore both response values but still require this call to close them.
  void resolveJavaScriptDialog(
    int requestId, {
    bool confirmed = false,
    String? promptText,
  }) {
    _ensureAlive();
    final nativePromptText = promptText?.toNativeUtf8();
    try {
      _checkStatus(
        'JavaScript dialog resolution',
        webviewFlutterLinuxWpeScriptDialogResolve(
          handle,
          requestId,
          confirmed ? 1 : 0,
          nativePromptText?.cast() ?? nullptr,
        ),
      );
    } finally {
      if (nativePromptText != null) calloc.free(nativePromptText);
    }
  }

  String _copyJavaScriptDialogField(int field, String description) {
    final length = webviewFlutterLinuxWpeScriptDialogRequestFieldLength(
      handle,
      field,
    );
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeScriptDialogRequestCopyField(
        handle,
        field,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE JavaScript dialog $description read failed with status $copied.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  /// Delivers each new HTML file-input request to Dart exactly once.
  ///
  /// Every returned request remains retained by WebKit until the application
  /// calls [selectFileChooserRequest] or [cancelFileChooserRequest].
  List<NativeFileChooserRequest> takeFileChooserRequests() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeFileChooserRequestCount(handle);
    final requests = <NativeFileChooserRequest>[];
    for (var requestIndex = 0; requestIndex < pending; requestIndex += 1) {
      final request = NativeFileChooserRequest(
        id: webviewFlutterLinuxWpeFileChooserRequestId(handle),
        allowsMultiple:
            webviewFlutterLinuxWpeFileChooserRequestAllowsMultiple(handle) != 0,
        acceptedMimeTypes: _copyFileChooserValues(0, 'accepted MIME type'),
        selectedFiles: _copyFileChooserValues(1, 'selected file'),
      );
      _checkStatus(
        'file chooser request delivery',
        webviewFlutterLinuxWpeFileChooserRequestTake(handle),
      );
      requests.add(request);
    }
    return requests;
  }

  /// Supplies absolute filesystem paths for one delivered file-input request.
  void selectFileChooserRequest(int requestId, List<String> files) {
    _ensureAlive();
    if (files.isEmpty) {
      throw ArgumentError.value(
        files,
        'files',
        'Must contain at least one path.',
      );
    }
    final nativeFiles = calloc<Pointer<Char>>(files.length);
    final allocatedStrings = <Pointer<Utf8>>[];
    try {
      for (var index = 0; index < files.length; index += 1) {
        final nativeFile = files[index].toNativeUtf8();
        allocatedStrings.add(nativeFile);
        nativeFiles[index] = nativeFile.cast<Char>();
      }
      _checkStatus(
        'file chooser selection',
        webviewFlutterLinuxWpeFileChooserRequestSelect(
          handle,
          requestId,
          nativeFiles,
          files.length,
        ),
      );
    } finally {
      for (final nativeFile in allocatedStrings) {
        calloc.free(nativeFile);
      }
      calloc.free(nativeFiles);
    }
  }

  /// Cancels one delivered file-input request without selecting a file.
  void cancelFileChooserRequest(int requestId) {
    _ensureAlive();
    _checkStatus(
      'file chooser cancellation',
      webviewFlutterLinuxWpeFileChooserRequestCancel(handle, requestId),
    );
  }

  List<String> _copyFileChooserValues(int collection, String description) {
    final count = webviewFlutterLinuxWpeFileChooserRequestValueCount(
      handle,
      collection,
    );
    return List<String>.generate(count, (index) {
      final length = webviewFlutterLinuxWpeFileChooserRequestValueLength(
        handle,
        collection,
        index,
      );
      // A non-null destination is required by the native ABI even for a valid
      // empty string, so reserve one byte while reporting the real capacity.
      final destination = calloc<Uint8>(length == 0 ? 1 : length);
      try {
        final copied = webviewFlutterLinuxWpeFileChooserRequestCopyValue(
          handle,
          collection,
          index,
          destination,
          length,
        );
        if (copied < 0) {
          throw StateError(
            'WPE file chooser $description read failed with status $copied.',
          );
        }
        return utf8.decode(
          destination.asTypedList(copied),
          allowMalformed: true,
        );
      } finally {
        calloc.free(destination);
      }
    }, growable: false);
  }

  /// Transfers every related child that WebKit has declared ready to show.
  ///
  /// Native ownership moves from the opener only after the URL and child
  /// handle have been copied successfully. Each returned renderer therefore
  /// needs a popup controller or explicit disposal. If delivery of a later
  /// request fails, renderers already transferred during this call are
  /// disposed before the error is rethrown.
  List<NativePopupRequest> takePopupRequests() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpePopupRequestCount(handle);
    final requests = <NativePopupRequest>[];
    try {
      for (var index = 0; index < pending; index += 1) {
        final childHandle = webviewFlutterLinuxWpePopupRequestChildHandle(
          handle,
        );
        if (childHandle <= 0) {
          throw StateError('WPE returned an invalid popup child handle.');
        }
        final length = webviewFlutterLinuxWpePopupRequestUrlLength(handle);
        final destination = calloc<Uint8>(length == 0 ? 1 : length);
        late final String url;
        try {
          final copied = webviewFlutterLinuxWpePopupRequestCopyUrl(
            handle,
            destination,
            length,
          );
          if (copied < 0) {
            throw StateError('WPE popup URL read failed with status $copied.');
          }
          url = utf8.decode(
            destination.asTypedList(copied),
            allowMalformed: true,
          );
        } finally {
          calloc.free(destination);
        }
        _checkStatus(
          'popup ownership transfer',
          webviewFlutterLinuxWpePopupRequestTake(handle),
        );
        requests.add(
          NativePopupRequest(
            url: url,
            renderer: NativeFrameRenderer.adopt(nativeHandle: childHandle),
          ),
        );
      }
      return requests;
    } catch (_) {
      for (final request in requests) {
        request.renderer.dispose();
      }
      rethrow;
    }
  }

  /// Consumes a JavaScript `window.close()` request for this view.
  bool takeWindowCloseRequest() {
    _ensureAlive();
    final status = webviewFlutterLinuxWpeCloseRequestedTake(handle);
    if (status < 0) {
      throw StateError(
        'WPE window-close request read failed with status $status.',
      );
    }
    return status != 0;
  }

  /// Drains HTML fullscreen enter/leave transitions in native order.
  List<bool> takeFullscreenEvents() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeFullscreenEventCount(handle);
    final events = <bool>[];
    for (var index = 0; index < pending; index += 1) {
      events.add(webviewFlutterLinuxWpeFullscreenEventValue(handle) != 0);
      _checkStatus(
        'fullscreen event acknowledgement',
        webviewFlutterLinuxWpeFullscreenEventPop(handle),
      );
    }
    return events;
  }

  /// Refreshes WebKit's native AT-SPI tree and returns its immutable mirror.
  ///
  /// Native traversal runs on a dedicated worker. This call returns the latest
  /// completed immutable snapshot and queues at most one later refresh, so it
  /// never waits for the web process. Callers should still poll only while
  /// Flutter semantics are enabled. [maximumNodes] is clamped natively to the
  /// package's defensive upper bound.
  NativeAccessibilityTree refreshAccessibilityTree({int maximumNodes = 1024}) {
    _ensureAlive();
    final generation = webviewFlutterLinuxWpeAccessibilityRefresh(
      handle,
      maximumNodes.clamp(1, 2048),
    );
    if (generation == 0) {
      throw StateError('WPE accessibility refresh returned no generation.');
    }
    final length = webviewFlutterLinuxWpeAccessibilityJsonLength(handle);
    if (length <= 0) {
      throw StateError('WPE accessibility refresh returned no snapshot.');
    }
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeAccessibilityCopyJson(
        handle,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE accessibility snapshot read failed with status $copied.',
        );
      }
      final tree = NativeAccessibilityTree.fromJson(
        utf8.decode(destination.asTypedList(copied), allowMalformed: true),
      );
      if (tree.generation != generation) {
        throw StateError(
          'WPE accessibility snapshot changed while it was being copied.',
        );
      }
      return tree;
    } finally {
      calloc.free(destination);
    }
  }

  /// Invokes one native action advertised by [node] in [tree].
  void performAccessibilityAction(
    NativeAccessibilityTree tree,
    NativeAccessibilityNode node,
    int actionIndex,
  ) {
    _ensureAlive();
    _checkStatus(
      'accessibility action',
      webviewFlutterLinuxWpeAccessibilityDoAction(
        handle,
        tree.generation,
        node.index,
        actionIndex,
      ),
    );
  }

  /// Moves browser focus to [node] through its native ATK component.
  void focusAccessibilityNode(
    NativeAccessibilityTree tree,
    NativeAccessibilityNode node,
  ) {
    _ensureAlive();
    _checkStatus(
      'accessibility focus',
      webviewFlutterLinuxWpeAccessibilityGrabFocus(
        handle,
        tree.generation,
        node.index,
      ),
    );
  }

  /// Replaces text in one native editable accessibility node.
  void setAccessibilityText(
    NativeAccessibilityTree tree,
    NativeAccessibilityNode node,
    String text,
  ) {
    _ensureAlive();
    final nativeText = text.toNativeUtf8();
    try {
      _checkStatus(
        'accessibility text update',
        webviewFlutterLinuxWpeAccessibilitySetText(
          handle,
          tree.generation,
          node.index,
          nativeText.cast(),
        ),
      );
    } finally {
      calloc.free(nativeText);
    }
  }

  /// Updates the UTF-16-compatible selection offsets of a native text node.
  void setAccessibilitySelection(
    NativeAccessibilityTree tree,
    NativeAccessibilityNode node,
    int start,
    int end,
  ) {
    _ensureAlive();
    _checkStatus(
      'accessibility selection update',
      webviewFlutterLinuxWpeAccessibilitySetSelection(
        handle,
        tree.generation,
        node.index,
        start,
        end,
      ),
    );
  }

  /// Adjusts a native range value by one advertised increment.
  void adjustAccessibilityValue(
    NativeAccessibilityTree tree,
    NativeAccessibilityNode node,
    int direction,
  ) {
    _ensureAlive();
    _checkStatus(
      'accessibility value adjustment',
      webviewFlutterLinuxWpeAccessibilityAdjustValue(
        handle,
        tree.generation,
        node.index,
        direction,
      ),
    );
  }

  /// Delivers each native download destination request to Dart exactly once.
  ///
  /// WebKit remains paused until [resolveDownloadRequest] supplies an absolute
  /// path or cancels the request. This keeps a headless view from silently
  /// writing to the user's default Downloads directory.
  List<NativeDownloadRequest> takeDownloadRequests() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeDownloadRequestCount(handle);
    final requests = <NativeDownloadRequest>[];
    for (var index = 0; index < pending; index += 1) {
      final mimeType = _copyDownloadRequestField(2, 'MIME type');
      final contentLength = webviewFlutterLinuxWpeDownloadRequestContentLength(
        handle,
      );
      requests.add(
        NativeDownloadRequest(
          id: webviewFlutterLinuxWpeDownloadRequestId(handle),
          uri: _copyDownloadRequestField(0, 'URI'),
          suggestedFilename: _copyDownloadRequestField(1, 'suggested filename'),
          mimeType: mimeType.isEmpty ? null : mimeType,
          contentLength: contentLength < 0 ? null : contentLength,
        ),
      );
      _checkStatus(
        'download request delivery',
        webviewFlutterLinuxWpeDownloadRequestTake(handle),
      );
    }
    return requests;
  }

  /// Supplies a local destination or cancels one delivered download request.
  ///
  /// A null [destination] cancels. Path validation belongs to the controller's
  /// public Linux API; this method only owns temporary native string memory.
  void resolveDownloadRequest(
    int requestId, {
    required String? destination,
    bool allowOverwrite = false,
  }) {
    _ensureAlive();
    final nativeDestination = destination?.toNativeUtf8();
    try {
      _checkStatus(
        destination == null
            ? 'download cancellation'
            : 'download destination selection',
        webviewFlutterLinuxWpeDownloadRequestResolve(
          handle,
          requestId,
          nativeDestination?.cast() ?? nullptr,
          allowOverwrite ? 1 : 0,
        ),
      );
    } finally {
      if (nativeDestination != null) calloc.free(nativeDestination);
    }
  }

  /// Copies and removes all currently queued download lifecycle transitions.
  List<NativeDownloadEvent> takeDownloadEvents() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeDownloadEventCount(handle);
    final events = <NativeDownloadEvent>[];
    for (var index = 0; index < pending; index += 1) {
      final kindValue = webviewFlutterLinuxWpeDownloadEventKind(handle);
      final kind = NativeDownloadEventKind.fromWireValue(kindValue);
      if (kind == null) {
        _checkStatus(
          'unknown download event removal',
          webviewFlutterLinuxWpeDownloadEventPop(handle),
        );
        throw StateError('WPE returned an unknown download event: $kindValue.');
      }
      final contentLength = webviewFlutterLinuxWpeDownloadEventContentLength(
        handle,
      );
      final destination = _copyDownloadEventField(0, 'destination');
      final detail = _copyDownloadEventField(1, 'error detail');
      events.add(
        NativeDownloadEvent(
          id: webviewFlutterLinuxWpeDownloadEventId(handle),
          kind: kind,
          receivedBytes: webviewFlutterLinuxWpeDownloadEventReceivedBytes(
            handle,
          ),
          contentLength: contentLength < 0 ? null : contentLength,
          errorCode: webviewFlutterLinuxWpeDownloadEventErrorCode(handle),
          destination: destination.isEmpty ? null : destination,
          detail: detail.isEmpty ? null : detail,
        ),
      );
      _checkStatus(
        'download event removal',
        webviewFlutterLinuxWpeDownloadEventPop(handle),
      );
    }
    return events;
  }

  String _copyDownloadRequestField(int field, String description) {
    final length = webviewFlutterLinuxWpeDownloadRequestFieldLength(
      handle,
      field,
    );
    final destination = calloc<Uint8>(length == 0 ? 1 : length);
    try {
      final copied = webviewFlutterLinuxWpeDownloadRequestCopyField(
        handle,
        field,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE download $description read failed with status $copied.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  String _copyDownloadEventField(int field, String description) {
    final length = webviewFlutterLinuxWpeDownloadEventFieldLength(
      handle,
      field,
    );
    final destination = calloc<Uint8>(length == 0 ? 1 : length);
    try {
      final copied = webviewFlutterLinuxWpeDownloadEventCopyField(
        handle,
        field,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE download $description read failed with status $copied.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  /// Delivers each new WebKit permission request to Dart exactly once.
  List<NativePermissionRequest> takePermissionRequests() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpePermissionRequestCount(handle);
    final requests = <NativePermissionRequest>[];
    for (var index = 0; index < pending; index += 1) {
      final request = NativePermissionRequest(
        id: webviewFlutterLinuxWpePermissionRequestId(handle),
        resourceTypes: webviewFlutterLinuxWpePermissionRequestResourceTypes(
          handle,
        ),
        url: _copyPermissionRequestUrl(),
      );
      _checkStatus(
        'permission request delivery',
        webviewFlutterLinuxWpePermissionRequestTake(handle),
      );
      requests.add(request);
    }
    return requests;
  }

  /// Grants or denies a permission request previously delivered to Dart.
  void resolvePermissionRequest(int requestId, {required bool allow}) {
    _ensureAlive();
    _checkStatus(
      'permission request resolution',
      webviewFlutterLinuxWpePermissionRequestResolve(
        handle,
        requestId,
        allow ? 1 : 0,
      ),
    );
  }

  /// Delivers each page-created notification to Flutter exactly once.
  List<NativeWebNotification> takeNotifications() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeNotificationCount(handle);
    final notifications = <NativeWebNotification>[];
    for (var index = 0; index < pending; index += 1) {
      final hasTag = webviewFlutterLinuxWpeNotificationHasTag(handle) != 0;
      final notification = NativeWebNotification(
        id: webviewFlutterLinuxWpeNotificationId(handle),
        title: _copyNotificationField(0, 'title'),
        body: _copyNotificationField(1, 'body'),
        tag: hasTag ? _copyNotificationField(2, 'tag') : null,
        url: _copyNotificationField(3, 'source URL'),
      );
      _checkStatus(
        'notification delivery',
        webviewFlutterLinuxWpeNotificationTake(handle),
      );
      notifications.add(notification);
    }
    return notifications;
  }

  /// Reports a user click while keeping the notification active.
  void clickNotification(int notificationId) {
    _ensureAlive();
    _checkStatus(
      'notification click',
      webviewFlutterLinuxWpeNotificationRespond(handle, notificationId, 1),
    );
  }

  /// Closes one active notification and releases its native lifetime.
  void closeNotification(int notificationId) {
    _ensureAlive();
    _checkStatus(
      'notification close',
      webviewFlutterLinuxWpeNotificationRespond(handle, notificationId, 0),
    );
  }

  /// Removes IDs for notifications withdrawn by page script or navigation.
  List<int> takeClosedNotificationIds() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeNotificationClosedCount(handle);
    return <int>[
      for (var index = 0; index < pending; index += 1)
        webviewFlutterLinuxWpeNotificationClosedTake(handle),
    ];
  }

  String _copyNotificationField(int field, String description) {
    final length = webviewFlutterLinuxWpeNotificationFieldLength(handle, field);
    final destination = calloc<Uint8>(length == 0 ? 1 : length);
    try {
      final copied = webviewFlutterLinuxWpeNotificationCopyField(
        handle,
        field,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE notification $description read failed with status $copied.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  String _copyPermissionRequestUrl() {
    final length = webviewFlutterLinuxWpePermissionRequestUrlLength(handle);
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpePermissionRequestCopyUrl(
        handle,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE permission request URL read failed with status $copied.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  /// Delivers each new HTTP-authentication challenge to Dart exactly once.
  ///
  /// The retained native request moves into a pending-response map before this
  /// method returns. Every result must therefore call either
  /// [proceedHttpAuthRequest] or [cancelHttpAuthRequest].
  List<NativeHttpAuthRequest> takeHttpAuthRequests() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeHttpAuthRequestCount(handle);
    final requests = <NativeHttpAuthRequest>[];
    for (var index = 0; index < pending; index += 1) {
      final hasRealm =
          webviewFlutterLinuxWpeHttpAuthRequestHasRealm(handle) != 0;
      final request = NativeHttpAuthRequest(
        id: webviewFlutterLinuxWpeHttpAuthRequestId(handle),
        host: _copyHttpAuthRequestField(0, 'host'),
        realm: hasRealm ? _copyHttpAuthRequestField(1, 'realm') : null,
      );
      _checkStatus(
        'HTTP authentication request delivery',
        webviewFlutterLinuxWpeHttpAuthRequestTake(handle),
      );
      requests.add(request);
    }
    return requests;
  }

  /// Supplies credentials for an HTTP-authentication request exactly once.
  void proceedHttpAuthRequest(
    int requestId, {
    required String username,
    required String password,
  }) {
    _ensureAlive();
    final nativeUsername = username.toNativeUtf8();
    final nativePassword = password.toNativeUtf8();
    try {
      _checkStatus(
        'HTTP authentication request credentials',
        webviewFlutterLinuxWpeHttpAuthRequestProceed(
          handle,
          requestId,
          nativeUsername.cast(),
          nativePassword.cast(),
        ),
      );
    } finally {
      calloc.free(nativeUsername);
      calloc.free(nativePassword);
    }
  }

  /// Cancels an HTTP-authentication request exactly once.
  void cancelHttpAuthRequest(int requestId) {
    _ensureAlive();
    _checkStatus(
      'HTTP authentication request cancellation',
      webviewFlutterLinuxWpeHttpAuthRequestCancel(handle, requestId),
    );
  }

  String _copyHttpAuthRequestField(int field, String description) {
    final length = webviewFlutterLinuxWpeHttpAuthRequestFieldLength(
      handle,
      field,
    );
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeHttpAuthRequestCopyField(
        handle,
        field,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE HTTP authentication $description read failed with status '
          '$copied.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  /// Delivers each TLS certificate failure to Dart exactly once.
  List<NativeSslAuthError> takeSslAuthErrors() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeSslAuthErrorCount(handle);
    final errors = <NativeSslAuthError>[];
    for (var index = 0; index < pending; index += 1) {
      final error = NativeSslAuthError(
        id: webviewFlutterLinuxWpeSslAuthErrorId(handle),
        url: _copySslAuthErrorUrl(),
        errorFlags: webviewFlutterLinuxWpeSslAuthErrorFlags(handle),
        certificateDer: _copySslAuthErrorCertificate(),
      );
      _checkStatus(
        'TLS certificate-error delivery',
        webviewFlutterLinuxWpeSslAuthErrorTake(handle),
      );
      errors.add(error);
    }
    return errors;
  }

  /// Proceeds past or cancels a TLS certificate failure exactly once.
  ///
  /// Proceeding installs an exception for the exact certificate and host in
  /// WPE's network session, then reloads the failed URL.
  void resolveSslAuthError(int requestId, {required bool proceed}) {
    _ensureAlive();
    _checkStatus(
      'TLS certificate-error resolution',
      webviewFlutterLinuxWpeSslAuthErrorResolve(
        handle,
        requestId,
        proceed ? 1 : 0,
      ),
    );
  }

  String _copySslAuthErrorUrl() {
    final length = webviewFlutterLinuxWpeSslAuthErrorUrlLength(handle);
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeSslAuthErrorCopyUrl(
        handle,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE TLS certificate-error URL read failed with status $copied.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  Uint8List _copySslAuthErrorCertificate() {
    final length = webviewFlutterLinuxWpeSslAuthErrorCertificateLength(handle);
    if (length == 0) return Uint8List(0);
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeSslAuthErrorCopyCertificate(
        handle,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE TLS certificate read failed with status $copied.',
        );
      }
      return Uint8List.fromList(destination.asTypedList(copied));
    } finally {
      calloc.free(destination);
    }
  }

  String _copyJavaScriptMessageText(
    int length,
    int Function(int, Pointer<Uint8>, int) copy,
    String field,
  ) {
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = copy(handle, destination, length);
      if (copied < 0) {
        throw StateError(
          'WPE JavaScript message $field read failed with status $copied.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  /// Drains lifecycle events emitted by WebKit since the previous pump.
  ///
  /// Every native snapshot is popped after its scalar fields and owned URL
  /// bytes are copied. Unknown future kinds are discarded safely, allowing a
  /// newer native library to add events without corrupting the existing queue.
  List<NativeNavigationEvent> takeNavigationEvents() {
    _ensureAlive();
    final pending = webviewFlutterLinuxWpeNavigationEventCount(handle);
    final events = <NativeNavigationEvent>[];
    for (var index = 0; index < pending; index += 1) {
      final kind = NativeNavigationEventKind.fromWireValue(
        webviewFlutterLinuxWpeNavigationEventKind(handle),
      );
      final progress = webviewFlutterLinuxWpeNavigationEventProgress(
        handle,
      ).clamp(0, 100);
      final code = webviewFlutterLinuxWpeNavigationEventCode(handle);
      final isMainFrame =
          webviewFlutterLinuxWpeNavigationEventIsMainFrame(handle) != 0;
      final detail = _copyNavigationEventDetail();
      final length = webviewFlutterLinuxWpeNavigationEventUrlLength(handle);
      var url = '';
      if (length > 0) {
        final destination = calloc<Uint8>(length);
        try {
          final copied = webviewFlutterLinuxWpeNavigationEventCopyUrl(
            handle,
            destination,
            length,
          );
          if (copied < 0) {
            throw StateError(
              'WPE navigation URL read failed with status $copied.',
            );
          }
          url = utf8.decode(
            destination.asTypedList(copied),
            allowMalformed: true,
          );
        } finally {
          calloc.free(destination);
        }
      }
      _checkStatus(
        'navigation event acknowledgement',
        webviewFlutterLinuxWpeNavigationEventPop(handle),
      );
      if (kind != null) {
        if (kind == NativeNavigationEventKind.webProcessTerminated) {
          _failPendingOperations(
            StateError(
              detail.isEmpty
                  ? 'The WebKit web process terminated before an asynchronous operation completed.'
                  : detail,
            ),
          );
        }
        events.add(
          NativeNavigationEvent(
            kind: kind,
            url: url,
            progress: progress,
            code: code,
            detail: detail,
            isMainFrame: isMainFrame,
          ),
        );
      }
    }
    return events;
  }

  /// Completes all in-flight request futures with [error] exactly once.
  ///
  /// WebKit may never deliver an asynchronous callback after its content
  /// process exits. Clearing the map before invoking completers also makes this
  /// safe if application error handlers synchronously submit replacement work.
  void _failPendingOperations(Object error) {
    final pending = _pendingJavaScript.values.toList(growable: false);
    _pendingJavaScript.clear();
    final stackTrace = StackTrace.current;
    for (final completer in pending) {
      completer.completeError(error, stackTrace);
    }
  }

  /// Intentionally exits the current web process for recovery tests.
  ///
  /// This invokes WebKit's deterministic termination API. The native WebView
  /// and Flutter texture stay allocated so a subsequent navigation can launch
  /// a replacement process. Production applications must not call this.
  void terminateWebProcessForTesting() {
    _ensureAlive();
    _checkStatus(
      'intentional WebKit web-process termination',
      webviewFlutterLinuxWpeTerminateWebProcessForTesting(handle),
    );
  }

  String _copyNavigationEventDetail() {
    final length = webviewFlutterLinuxWpeNavigationEventDetailLength(handle);
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeNavigationEventCopyDetail(
        handle,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE navigation detail read failed with status $copied.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  /// Resizes the browser surface from logical Flutter dimensions.
  ///
  /// WPE receives an integer logical viewport plus Flutter's scale separately,
  /// allowing it to expose correct CSS dimensions and `devicePixelRatio` while
  /// allocating a sharp physical render buffer.
  void resizeSurface({
    required double logicalWidth,
    required double logicalHeight,
    required double deviceScaleFactor,
  }) {
    _ensureAlive();
    final geometry = normalizeWpeSurfaceGeometry(
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      deviceScaleFactor: deviceScaleFactor,
    );
    _deviceScaleFactor = geometry.scale;
    _checkStatus(
      'surface resize',
      webviewFlutterLinuxWpeResize(
        handle,
        geometry.logicalWidth,
        geometry.logicalHeight,
        geometry.scale,
      ),
    );
  }

  /// Updates native keyboard focus.
  void setFocus(bool focused) {
    _ensureAlive();
    _checkStatus(
      'focus',
      webviewFlutterLinuxWpeSetFocus(handle, focused ? 1 : 0),
    );
  }

  /// Returns the newest complete browser editable-state snapshot, if changed.
  ///
  /// Native selection offsets are UTF-8 byte indexes. They are converted here
  /// because Flutter's [TextEditingValue] indexes Dart UTF-16 code units.
  NativeBrowserInputMethodState? takeInputMethodState() {
    _ensureAlive();
    final generation = webviewFlutterLinuxWpeInputMethodGeneration(handle);
    if (generation == 0 || generation == _lastInputMethodGeneration) {
      return null;
    }
    _lastInputMethodGeneration = generation;
    final focused = webviewFlutterLinuxWpeInputMethodFocused(handle);
    if (focused < 0) {
      throw StateError('WPE input-method focus query failed.');
    }
    final length = webviewFlutterLinuxWpeInputMethodTextLength(handle);
    var text = '';
    if (length > 0) {
      final destination = calloc<Uint8>(length);
      try {
        final copied = webviewFlutterLinuxWpeInputMethodCopyText(
          handle,
          destination,
          length,
        );
        if (copied < 0) {
          throw StateError(
            'WPE input-method surrounding-text read failed with status '
            '$copied.',
          );
        }
        text = utf8.decode(
          destination.asTypedList(copied),
          allowMalformed: true,
        );
      } finally {
        calloc.free(destination);
      }
    }
    final cursor = utf8ByteOffsetToUtf16(
      text,
      webviewFlutterLinuxWpeInputMethodCursorIndex(handle),
    );
    final selection = utf8ByteOffsetToUtf16(
      text,
      webviewFlutterLinuxWpeInputMethodSelectionIndex(handle),
    );
    return NativeBrowserInputMethodState(
      focused: focused != 0,
      text: text,
      selection: TextSelection(baseOffset: selection, extentOffset: cursor),
      caretRect: Rect.fromLTWH(
        webviewFlutterLinuxWpeInputMethodCursorX(handle).toDouble(),
        webviewFlutterLinuxWpeInputMethodCursorY(handle).toDouble(),
        webviewFlutterLinuxWpeInputMethodCursorWidth(handle).toDouble(),
        webviewFlutterLinuxWpeInputMethodCursorHeight(handle).toDouble(),
      ),
      inputPurpose: webviewFlutterLinuxWpeInputMethodPurpose(handle),
      inputHints: webviewFlutterLinuxWpeInputMethodHints(handle),
    );
  }

  /// Replaces the active browser composition without committing it.
  void setInputMethodPreedit(String text, int cursorOffset) {
    _ensureAlive();
    final nativeText = text.toNativeUtf8();
    try {
      _checkStatus(
        'input-method preedit update',
        webviewFlutterLinuxWpeInputMethodSetPreedit(
          handle,
          nativeText.cast(),
          cursorOffset,
        ),
      );
    } finally {
      calloc.free(nativeText);
    }
  }

  /// Commits a completed platform input-method sequence into WebKit.
  void commitInputMethodText(String text) {
    _ensureAlive();
    final nativeText = text.toNativeUtf8();
    try {
      _checkStatus(
        'input-method commit',
        webviewFlutterLinuxWpeInputMethodCommit(handle, nativeText.cast()),
      );
    } finally {
      calloc.free(nativeText);
    }
  }

  /// Cancels the active browser composition.
  void cancelInputMethodPreedit() {
    _ensureAlive();
    _checkStatus(
      'input-method preedit cancellation',
      webviewFlutterLinuxWpeInputMethodCancelPreedit(handle),
    );
  }

  /// Deletes Unicode characters relative to the active browser cursor.
  void deleteInputMethodSurrounding(int offset, int characterCount) {
    _ensureAlive();
    _checkStatus(
      'input-method surrounding deletion',
      webviewFlutterLinuxWpeInputMethodDeleteSurrounding(
        handle,
        offset,
        characterCount,
      ),
    );
  }

  /// Updates native page visibility and rendering activity.
  void setVisibility(bool visible) {
    _ensureAlive();
    _checkStatus(
      'visibility',
      webviewFlutterLinuxWpeSetVisibility(handle, visible ? 1 : 0),
    );
  }

  /// Updates whether pages may execute JavaScript.
  void setJavaScriptEnabled(bool enabled) {
    _ensureAlive();
    _checkStatus(
      'JavaScript mode update',
      webviewFlutterLinuxWpeSetJavaScriptEnabled(handle, enabled ? 1 : 0),
    );
  }

  /// Installs compiled ad-block rules for the web-process extension.
  ///
  /// The blob is copied into the shared extension directory and picked up by
  /// the web process on its next navigation. Pass an empty blob to disable.
  void setContentBlockRules(List<int> rulesBlob) {
    final nativeBytes = rulesBlob.isEmpty
        ? nullptr
        : calloc<Uint8>(rulesBlob.length)..asTypedList(rulesBlob.length).setAll(0, rulesBlob);
    try {
      _checkStatus(
        'content-block rules installation',
        webviewFlutterLinuxSetContentBlockRules(
          nativeBytes.cast(),
          rulesBlob.length,
        ),
      );
    } finally {
      if (nativeBytes != nullptr) calloc.free(nativeBytes);
    }
  }

  /// Returns and drains the ad-blocked request count for this view.
  int takeBlockedCount() {
    _ensureAlive();
    return webviewFlutterLinuxTakeBlockedCount(handle);
  }

  /// Sets whether WebKit requires a user gesture before media playback.
  void setMediaPlaybackRequiresUserGesture(bool required) {
    _ensureAlive();
    _checkStatus(
      'media playback policy update',
      webviewFlutterLinuxWpeSetMediaPlaybackRequiresUserGesture(
        handle,
        required ? 1 : 0,
      ),
    );
  }

  /// Sets whether media elements may play inline inside the document.
  void setMediaPlaybackAllowsInline(bool allowed) {
    _ensureAlive();
    _checkStatus(
      'inline media playback policy update',
      webviewFlutterLinuxWpeSetMediaPlaybackAllowsInline(
        handle,
        allowed ? 1 : 0,
      ),
    );
  }

  /// Enables or disables WebRTC and WPE's associated MediaStream support.
  void setWebRtcEnabled(bool enabled) {
    _ensureAlive();
    _checkStatus(
      'WebRTC capability update',
      webviewFlutterLinuxWpeSetWebRtcEnabled(handle, enabled ? 1 : 0),
    );
  }

  /// Enables deterministic WebKit camera and microphone devices.
  ///
  /// Permission requests still flow through the normal Flutter callback; this
  /// only removes host-hardware availability from automated browser tests.
  void setMockCaptureDevicesEnabled(bool enabled) {
    _ensureAlive();
    _checkStatus(
      'mock capture-device update',
      webviewFlutterLinuxWpeSetMockCaptureDevicesEnabled(
        handle,
        enabled ? 1 : 0,
      ),
    );
  }

  /// Whether WebKit currently exposes deterministic capture devices.
  bool get mockCaptureDevicesEnabled {
    _ensureAlive();
    final enabled = webviewFlutterLinuxWpeMockCaptureDevicesEnabled(handle);
    if (enabled < 0) {
      throw StateError(
        'Mock capture-device query failed with status $enabled.',
      );
    }
    return enabled != 0;
  }

  /// Enables or disables WebKit's Encrypted Media Extensions surface.
  void setEncryptedMediaEnabled(bool enabled) {
    _ensureAlive();
    _checkStatus(
      'encrypted media capability update',
      webviewFlutterLinuxWpeSetEncryptedMediaEnabled(handle, enabled ? 1 : 0),
    );
  }

  /// Enables or disables WebKit developer extras for this view.
  void setInspectable(bool inspectable) {
    _ensureAlive();
    _checkStatus(
      'inspectability update',
      webviewFlutterLinuxWpeSetInspectable(handle, inspectable ? 1 : 0),
    );
  }

  /// Enables or disables Geolocation API permission requests for this view.
  void setGeolocationEnabled(bool enabled) {
    _ensureAlive();
    _checkStatus(
      'geolocation capability update',
      webviewFlutterLinuxWpeSetGeolocationEnabled(handle, enabled ? 1 : 0),
    );
  }

  /// Whether the native per-view geolocation gate is enabled.
  bool get geolocationEnabled {
    _ensureAlive();
    final enabled = webviewFlutterLinuxWpeGeolocationEnabled(handle);
    if (enabled < 0) {
      throw StateError(
        'WPE geolocation capability query failed with status $enabled.',
      );
    }
    return enabled != 0;
  }

  /// Controls whether script-created windows require a user gesture.
  void setJavaScriptCanOpenWindowsAutomatically(bool enabled) {
    _ensureAlive();
    _checkStatus(
      'automatic JavaScript window policy update',
      webviewFlutterLinuxWpeSetJavaScriptCanOpenWindowsAutomatically(
        handle,
        enabled ? 1 : 0,
      ),
    );
  }

  /// Whether JavaScript may currently create a window without a gesture.
  bool get javaScriptCanOpenWindowsAutomatically {
    _ensureAlive();
    final enabled = webviewFlutterLinuxWpeJavaScriptCanOpenWindowsAutomatically(
      handle,
    );
    if (enabled < 0) {
      throw StateError(
        'WPE automatic JavaScript window query failed with status $enabled.',
      );
    }
    return enabled != 0;
  }

  /// Controls whether page scripts may execute clipboard editing commands.
  void setJavaScriptCanAccessClipboard(bool enabled) {
    _ensureAlive();
    _checkStatus(
      'JavaScript clipboard policy update',
      webviewFlutterLinuxWpeSetJavaScriptCanAccessClipboard(
        handle,
        enabled ? 1 : 0,
      ),
    );
  }

  /// Whether page scripts may currently execute clipboard editing commands.
  bool get javaScriptCanAccessClipboard {
    _ensureAlive();
    final enabled = webviewFlutterLinuxWpeJavaScriptCanAccessClipboard(handle);
    if (enabled < 0) {
      throw StateError(
        'WPE JavaScript clipboard policy query failed with status $enabled.',
      );
    }
    return enabled != 0;
  }

  /// Updates whether a local-file document may request adjacent local files.
  void setFileAccessEnabled(bool enabled) {
    _ensureAlive();
    _checkStatus(
      'local-file access update',
      webviewFlutterLinuxWpeSetFileAccessEnabled(handle, enabled ? 1 : 0),
    );
  }

  /// Updates whether file-origin documents may access arbitrary origins.
  void setUniversalFileAccessEnabled(bool enabled) {
    _ensureAlive();
    _checkStatus(
      'universal local-file access update',
      webviewFlutterLinuxWpeSetUniversalFileAccessEnabled(
        handle,
        enabled ? 1 : 0,
      ),
    );
  }

  /// Returns WPE's effective per-view capability bit field.
  int get capabilityFlags {
    _ensureAlive();
    final flags = webviewFlutterLinuxWpeCapabilityFlags(handle);
    if (flags < 0) {
      throw StateError('WPE capability query failed with status $flags.');
    }
    return flags;
  }

  /// Replaces the browser user agent, or restores the default when null.
  void setUserAgent(String? userAgent) {
    _ensureAlive();
    final nativeUserAgent = userAgent?.toNativeUtf8();
    try {
      _checkStatus(
        'user-agent update',
        webviewFlutterLinuxWpeSetUserAgent(
          handle,
          nativeUserAgent?.cast() ?? nullptr,
        ),
      );
    } finally {
      if (nativeUserAgent != null) calloc.free(nativeUserAgent);
    }
  }

  /// Returns WebKit's effective user agent for this view.
  String? getUserAgent() {
    _ensureAlive();
    return _copyOptionalWebViewText(
      description: 'user-agent',
      lengthOf: webviewFlutterLinuxWpeUserAgentLength,
      copy: webviewFlutterLinuxWpeCopyUserAgent,
    );
  }

  /// Returns WebKit's current main-frame URI.
  String? get currentUrl {
    _ensureAlive();
    return _copyOptionalWebViewText(
      description: 'URI',
      lengthOf: webviewFlutterLinuxWpeUriLength,
      copy: webviewFlutterLinuxWpeCopyUri,
    );
  }

  /// Returns WebKit's current document title without evaluating JavaScript.
  String? get title {
    _ensureAlive();
    return _copyOptionalWebViewText(
      description: 'title',
      lengthOf: webviewFlutterLinuxWpeTitleLength,
      copy: webviewFlutterLinuxWpeCopyTitle,
    );
  }

  String? _copyOptionalWebViewText({
    required String description,
    required int Function(int handle) lengthOf,
    required int Function(
      int handle,
      Pointer<Uint8> destination,
      int destinationLength,
    )
    copy,
  }) {
    final length = lengthOf(handle);
    if (length < 0) return null;
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = copy(handle, destination, length);
      if (copied < 0) {
        throw StateError('WPE $description read failed with status $copied.');
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  /// WebKit's current page zoom factor.
  double get zoomLevel {
    _ensureAlive();
    final zoom = webviewFlutterLinuxWpeZoomLevel(handle);
    if (zoom <= 0 || !zoom.isFinite) {
      throw StateError('WPE returned an invalid page zoom factor: $zoom.');
    }
    return zoom;
  }

  /// Applies a page zoom factor, clamped for usable touchpad interaction.
  void setZoomLevel(double zoomLevel) {
    _ensureAlive();
    final zoom = zoomLevel.clamp(0.25, 5).toDouble();
    _checkStatus(
      'page zoom update',
      webviewFlutterLinuxWpeSetZoomLevel(handle, zoom),
    );
  }

  /// Applies text-only zoom using an Android-compatible percentage.
  ///
  /// A value of 100 restores WPE's ordinary full-page zoom mode. Other values
  /// make WPE's shared zoom factor affect text and text-bearing controls only.
  void setTextZoom(int textZoom) {
    _ensureAlive();
    _checkStatus(
      'text zoom update',
      webviewFlutterLinuxWpeSetTextZoom(handle, textZoom),
    );
  }

  /// Effective text-only zoom percentage for this native view.
  int get textZoom {
    _ensureAlive();
    final percentage = webviewFlutterLinuxWpeTextZoom(handle);
    if (percentage < 10 || percentage > 1000) {
      throw StateError(
        'WPE returned an invalid text zoom percentage: $percentage.',
      );
    }
    return percentage;
  }

  /// Sets the color shown behind transparent page content.
  void setBackgroundColor(int argb) {
    _ensureAlive();
    _checkStatus(
      'background color update',
      webviewFlutterLinuxWpeSetBackgroundColor(handle, argb),
    );
  }

  /// Sends a pointer movement or leave event using logical coordinates.
  void sendMouseMove({
    required int x,
    required int y,
    required int modifiers,
    bool mouseLeave = false,
    bool mouseEnter = false,
  }) {
    if (mouseLeave && mouseEnter) {
      throw ArgumentError('A pointer transition cannot enter and leave.');
    }
    _ensureAlive();
    _checkStatus(
      'mouse move',
      webviewFlutterLinuxWpeSendMouseMove(
        handle,
        x,
        y,
        modifiers,
        mouseLeave ? 1 : (mouseEnter ? 2 : 0),
      ),
    );
  }

  /// Sends a pointer-button transition using logical coordinates.
  void sendMouseButton({
    required int x,
    required int y,
    required int modifiers,
    required int button,
    required bool mouseUp,
    int clickCount = 1,
  }) {
    _ensureAlive();
    _checkStatus(
      'mouse button',
      webviewFlutterLinuxWpeSendMouseButton(
        handle,
        x,
        y,
        modifiers,
        button,
        mouseUp ? 1 : 0,
        clickCount,
      ),
    );
  }

  /// Sends a wheel event using logical pointer coordinates.
  void sendMouseWheel({
    required int x,
    required int y,
    required int modifiers,
    required int deltaX,
    required int deltaY,
  }) {
    _ensureAlive();
    _checkStatus(
      'mouse wheel',
      webviewFlutterLinuxWpeSendMouseWheel(
        handle,
        x,
        y,
        modifiers,
        deltaX,
        deltaY,
      ),
    );
  }

  /// Sends one touchpad-scroll update or a terminating stop event.
  void sendTrackpadScroll({
    required int x,
    required int y,
    required int modifiers,
    required double deltaX,
    required double deltaY,
    bool isStop = false,
  }) {
    _ensureAlive();
    _checkStatus(
      'trackpad scroll',
      webviewFlutterLinuxWpeSendTrackpadScroll(
        handle,
        x,
        y,
        modifiers,
        deltaX,
        deltaY,
        isStop ? 1 : 0,
      ),
    );
  }

  /// Sends one touchscreen contact transition to WebKit.
  void sendTouch({
    required NativeTouchEventType eventType,
    required int sequenceId,
    required int x,
    required int y,
    int modifiers = 0,
  }) {
    _ensureAlive();
    _checkStatus(
      'touch ${eventType.name}',
      webviewFlutterLinuxWpeSendTouch(
        handle,
        eventType.index,
        modifiers,
        sequenceId,
        x,
        y,
      ),
    );
  }

  /// Sends a Chromium-compatible key event to WPE.
  void sendKey({
    required int eventType,
    required int modifiers,
    required int windowsKeyCode,
    required int nativeKeyCode,
    int character = 0,
    int unmodifiedCharacter = 0,
  }) {
    _ensureAlive();
    _checkStatus(
      'key',
      webviewFlutterLinuxWpeSendKey(
        handle,
        eventType,
        modifiers,
        windowsKeyCode,
        nativeKeyCode,
        character,
        unmodifiedCharacter,
      ),
    );
  }

  /// Copies [text] into the clipboard exposed to the browser process.
  void setClipboardText(String text) {
    _ensureAlive();
    final nativeText = text.toNativeUtf8();
    try {
      _checkStatus(
        'clipboard write',
        webviewFlutterLinuxWpeClipboardSetText(handle, nativeText.cast()),
      );
      _lastClipboardChangeCount = webviewFlutterLinuxWpeClipboardChangeCount(
        handle,
      );
    } finally {
      calloc.free(nativeText);
    }
  }

  /// Asynchronously imports every supported desktop clipboard format into WPE.
  ///
  /// The native worker performs Wayland/X11 selection I/O away from Flutter's
  /// platform thread. This method only polls request state and applies the
  /// already-owned bytes to WPE. It returns `false` when the native backend is
  /// unavailable so the widget can retain Flutter's plain-text fallback.
  Future<bool> importSystemClipboard({
    String? plainTextOverride,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    _ensureAlive();
    final requestId = webviewFlutterLinuxSystemClipboardImport();
    if (requestId == 0) return false;
    final nativePlainText = plainTextOverride?.toNativeUtf8();

    final deadline = DateTime.now().add(timeout);
    try {
      while (!_disposed && DateTime.now().isBefore(deadline)) {
        final status = webviewFlutterLinuxSystemClipboardRequestStatus(
          requestId,
        );
        if (status == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 8));
          continue;
        }
        if (status < 0) return false;
        final applied = webviewFlutterLinuxSystemClipboardApplyImport(
          handle,
          requestId,
          nativePlainText?.cast() ?? nullptr,
        );
        if (applied != 1) return false;
        // Importing changes WPE's local revision. Mark it observed so the next
        // frame does not echo the same desktop item back to its source.
        _lastClipboardChangeCount = webviewFlutterLinuxWpeClipboardChangeCount(
          handle,
        );
        return true;
      }
      return false;
    } finally {
      webviewFlutterLinuxSystemClipboardDiscard(requestId);
      if (nativePlainText != null) calloc.free(nativePlainText);
    }
  }

  /// Starts or advances rich browser-to-desktop clipboard synchronization.
  ///
  /// A non-null result is a plain-text fallback that Dart should publish only
  /// when the GTK-free native backend failed. Successful native exports retain
  /// HTML, images, URI lists, RTF, and bounded custom MIME representations.
  String? syncChangedClipboardToSystem() {
    _ensureAlive();
    if (_pendingClipboardExportRequest != 0) {
      final status = webviewFlutterLinuxSystemClipboardRequestStatus(
        _pendingClipboardExportRequest,
      );
      if (status == 0) return null;
      webviewFlutterLinuxSystemClipboardDiscard(_pendingClipboardExportRequest);
      _pendingClipboardExportRequest = 0;
      if (status < 0) return _copyClipboardText();
    }

    final changeCount = webviewFlutterLinuxWpeClipboardChangeCount(handle);
    if (changeCount < 0 || changeCount == _lastClipboardChangeCount) {
      return null;
    }
    _lastClipboardChangeCount = changeCount;
    final requestId = webviewFlutterLinuxSystemClipboardExport(handle);
    if (requestId == 0) return _copyClipboardText();
    _pendingClipboardExportRequest = requestId;
    return null;
  }

  /// Returns newly changed browser clipboard text, if any.
  ///
  /// The native revision counter prevents Flutter from repeatedly importing
  /// the same value. A `null` result means no new text is available, while an
  /// empty string represents a new empty clipboard value.
  String? takeClipboardText() {
    _ensureAlive();
    final changeCount = webviewFlutterLinuxWpeClipboardChangeCount(handle);
    if (changeCount < 0 || changeCount == _lastClipboardChangeCount) {
      return null;
    }
    _lastClipboardChangeCount = changeCount;
    return _copyClipboardText();
  }

  String? _copyClipboardText() {
    final length = webviewFlutterLinuxWpeClipboardTextLength(handle);
    if (length < 0) return null;
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeClipboardCopyText(
        handle,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError('WPE clipboard read failed with status $copied.');
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  /// Returns a newly exposed native context-menu snapshot, if any.
  ///
  /// WPE menu coordinates already use the view's logical coordinate space.
  NativeBrowserContextMenu? takeContextMenu() {
    _ensureAlive();
    final generation = webviewFlutterLinuxWpeContextMenuGeneration(handle);
    if (generation == 0 || generation == _lastContextMenuGeneration) {
      return null;
    }
    _lastContextMenuGeneration = generation;
    final itemCount = webviewFlutterLinuxWpeContextMenuItemCount(handle);
    final items = <BrowserContextMenuItem>[];
    for (var index = 0; index < itemCount; index += 1) {
      final length = webviewFlutterLinuxWpeContextMenuItemTitleLength(
        handle,
        index,
      );
      var title = '';
      if (length > 0) {
        final destination = calloc<Uint8>(length);
        try {
          final copied = webviewFlutterLinuxWpeContextMenuItemCopyTitle(
            handle,
            index,
            destination,
            length,
          );
          if (copied > 0) {
            title = utf8.decode(
              destination.asTypedList(copied),
              allowMalformed: true,
            );
          }
        } finally {
          calloc.free(destination);
        }
      }
      items.add(
        BrowserContextMenuItem(
          index: index,
          title: title.replaceAll(RegExp(r'[_&]'), ''),
          isSeparator:
              webviewFlutterLinuxWpeContextMenuItemIsSeparator(handle, index) !=
              0,
          isEnabled:
              webviewFlutterLinuxWpeContextMenuItemIsEnabled(handle, index) !=
              0,
          stockAction: webviewFlutterLinuxWpeContextMenuItemStockAction(
            handle,
            index,
          ),
        ),
      );
    }
    return NativeBrowserContextMenu(
      position: Offset(
        webviewFlutterLinuxWpeContextMenuX(handle),
        webviewFlutterLinuxWpeContextMenuY(handle),
      ),
      items: items,
    );
  }

  /// Activates the native context-menu entry at [index].
  void activateContextMenuItem(int index) {
    _ensureAlive();
    _checkStatus(
      'context-menu action',
      webviewFlutterLinuxWpeContextMenuActivate(handle, index),
    );
  }

  /// Dismisses the current native context menu when this renderer is alive.
  void dismissContextMenu() {
    if (!_disposed) webviewFlutterLinuxWpeContextMenuDismiss(handle);
  }

  /// Returns a newly exposed HTML option-menu snapshot, if any.
  ///
  /// Native bounds use WPE's logical view coordinates. A native close advances
  /// the generation but returns no menu.
  NativeBrowserOptionMenu? takeOptionMenu() {
    _ensureAlive();
    final generation = webviewFlutterLinuxWpeOptionMenuGeneration(handle);
    if (generation == 0 || generation == _lastOptionMenuGeneration) {
      return null;
    }
    _lastOptionMenuGeneration = generation;
    if (webviewFlutterLinuxWpeOptionMenuAvailable(handle) == 0) return null;

    final count = webviewFlutterLinuxWpeOptionMenuItemCount(handle);
    final items = List<BrowserOptionMenuItem>.generate(count, (index) {
      final tooltip = _copyOptionMenuItemField(index, 1, 'tooltip');
      return BrowserOptionMenuItem(
        index: index,
        label: _copyOptionMenuItemField(index, 0, 'label'),
        tooltip: tooltip.isEmpty ? null : tooltip,
        isGroupLabel:
            webviewFlutterLinuxWpeOptionMenuItemIsGroupLabel(handle, index) !=
            0,
        isGroupChild:
            webviewFlutterLinuxWpeOptionMenuItemIsGroupChild(handle, index) !=
            0,
        isEnabled:
            webviewFlutterLinuxWpeOptionMenuItemIsEnabled(handle, index) != 0,
        isSelected:
            webviewFlutterLinuxWpeOptionMenuItemIsSelected(handle, index) != 0,
      );
    }, growable: false);
    return NativeBrowserOptionMenu(
      bounds: Rect.fromLTWH(
        webviewFlutterLinuxWpeOptionMenuX(handle),
        webviewFlutterLinuxWpeOptionMenuY(handle),
        webviewFlutterLinuxWpeOptionMenuWidth(handle),
        webviewFlutterLinuxWpeOptionMenuHeight(handle),
      ),
      items: items,
    );
  }

  String _copyOptionMenuItemField(int index, int field, String description) {
    final length = webviewFlutterLinuxWpeOptionMenuItemFieldLength(
      handle,
      index,
      field,
    );
    if (length == 0) return '';
    final destination = calloc<Uint8>(length);
    try {
      final copied = webviewFlutterLinuxWpeOptionMenuItemCopyField(
        handle,
        index,
        field,
        destination,
        length,
      );
      if (copied < 0) {
        throw StateError(
          'WPE option menu $description read failed with status $copied.',
        );
      }
      return utf8.decode(destination.asTypedList(copied), allowMalformed: true);
    } finally {
      calloc.free(destination);
    }
  }

  /// Activates one enabled option and closes the retained browser menu.
  void activateOptionMenuItem(int index) {
    _ensureAlive();
    _checkStatus(
      'option-menu activation',
      webviewFlutterLinuxWpeOptionMenuActivate(handle, index),
    );
  }

  /// Closes the retained browser option menu without changing its value.
  void dismissOptionMenu() {
    if (!_disposed) webviewFlutterLinuxWpeOptionMenuDismiss(handle);
  }

  void _ensureAlive() {
    if (_disposed) {
      throw StateError('The Linux WebView renderer has been disposed.');
    }
  }

  static void _checkStatus(
    String operation,
    int status, {
    bool allowAlreadyInitialized = true,
  }) {
    if (status == 0 || (allowAlreadyInitialized && status == 1)) return;
    throw StateError('$operation failed with status $status.');
  }

  /// Releases this renderer's native view and external texture.
  ///
  /// Repeated calls are safe and do not cross the FFI boundary again.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_pendingClipboardExportRequest != 0) {
      webviewFlutterLinuxSystemClipboardDiscard(_pendingClipboardExportRequest);
      _pendingClipboardExportRequest = 0;
    }
    _failPendingOperations(
      StateError(
        'The Linux WebView was disposed before an asynchronous operation completed.',
      ),
    );
    try {
      _checkStatus(
        'native WebView disposal',
        webviewFlutterLinuxViewDispose(handle),
      );
    } finally {
      _finalizer.detach(this);
    }
  }
}
