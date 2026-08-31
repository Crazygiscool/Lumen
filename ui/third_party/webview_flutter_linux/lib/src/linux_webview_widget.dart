// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'linux_webview_controller.dart';
import 'native_frame_renderer.dart';
import 'webview_accessibility.dart';
import 'webview_cursor.dart';
import 'webview_gesture_router.dart';
import 'webview_text_input.dart';
import 'wpe_keyboard.dart';
import 'wpe_pointer.dart';

const _contextMenuActionCopy = 13;
const _contextMenuActionCut = 14;
const _contextMenuActionPaste = 15;

/// Builds the Flutter texture surface for a [LinuxWebViewController].
///
/// Pointer, keyboard, clipboard, lifecycle, and context-menu events cross the
/// Dart-to-Rust boundary through the controller-owned renderer leased by the
/// mounted surface.
class LinuxWebViewWidget extends PlatformWebViewWidget {
  /// Creates a widget delegate and verifies its controller is Linux-backed.
  LinuxWebViewWidget(PlatformWebViewWidgetCreationParams params)
    : super.implementation(params) {
    if (params.controller is! LinuxWebViewController) {
      throw ArgumentError.value(
        params.controller,
        'params.controller',
        'Expected a LinuxWebViewController.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: params.layoutDirection,
    child: _LinuxWebViewSurface(
      key: params.key,
      controller: params.controller as LinuxWebViewController,
      gestureRecognizers: params.gestureRecognizers,
    ),
  );
}

/// Owns the mounted relationship between a controller and native renderer.
class _LinuxWebViewSurface extends StatefulWidget {
  const _LinuxWebViewSurface({
    super.key,
    required this.controller,
    required this.gestureRecognizers,
  });

  final LinuxWebViewController controller;
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  @override
  State<_LinuxWebViewSurface> createState() => _LinuxWebViewSurfaceState();
}

/// Pumps native events and translates Flutter input for a WebView texture.
class _LinuxWebViewSurfaceState extends State<_LinuxWebViewSurface>
    with WidgetsBindingObserver, TextInputClient {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Linux WebView');
  final GlobalKey _surfaceKey = GlobalKey();
  final WpeScrollAccumulator _wheelScroll = WpeScrollAccumulator();
  final WpeClickCounter _clickCounter = WpeClickCounter();
  final WpeNavigationSwipeTracker _navigationSwipe =
      WpeNavigationSwipeTracker();
  NativeFrameRenderer? _renderer;
  Timer? _frameTimer;
  Object? _error;
  int _pressedButtons = 0;
  Offset _lastPointerPosition = Offset.zero;
  MouseCursor _mouseCursor = SystemMouseCursors.basic;
  NativeCustomBrowserCursor? _customCursor;
  ui.Image? _customCursorImage;
  bool _pointerInside = false;
  Size? _requestedSize;
  double? _requestedScale;
  double _panZoomStartZoom = 1;
  bool _trackpadDidScroll = false;
  bool _resizeScheduled = false;
  bool _contextMenuOpen = false;
  bool _optionMenuOpen = false;
  bool _surfaceFocused = false;
  TextInputConnection? _textInputConnection;
  TextEditingValue _editingValue = TextEditingValue.empty;
  NativeBrowserInputMethodState? _nativeInputMethodState;
  String? _lastSystemClipboardText;
  Future<void> _inputQueue = Future<void>.value();
  OverlayEntry? _fullscreenOverlay;
  bool _fullscreen = false;
  bool _fullscreenOverlayScheduled = false;
  NativeAccessibilityTree? _accessibilityTree;
  DateTime _nextAccessibilityPoll = DateTime.fromMillisecondsSinceEpoch(0);
  late bool _semanticsEnabled;
  late bool _applicationVisible;
  late WebViewGestureRouter _gestureRouter;
  int _attachmentGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _semanticsEnabled = SemanticsBinding.instance.semanticsEnabled;
    _applicationVisible = _isVisibleLifecycleState(
      WidgetsBinding.instance.lifecycleState,
    );
    SemanticsBinding.instance.addSemanticsEnabledListener(
      _handleSemanticsEnabledChanged,
    );
    _gestureRouter = _createGestureRouter();
    unawaited(_attach(widget.controller, _attachmentGeneration));
  }

  WebViewGestureRouter _createGestureRouter() => WebViewGestureRouter(
    _handleRoutedPointerEvent,
    widget.gestureRecognizers,
  );

  @override
  void didUpdateWidget(covariant _LinuxWebViewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _replaceController(oldWidget.controller);
    }
    if (!WebViewGestureRouter.hasSameFactoryTypes(
      oldWidget.gestureRecognizers,
      widget.gestureRecognizers,
    )) {
      _gestureRouter.dispose();
      _gestureRouter = _createGestureRouter();
    }
  }

  /// Releases the old presentation before asynchronously leasing the new one.
  ///
  /// The generation makes an old in-flight native creation harmless: when it
  /// eventually completes, it releases its own controller instead of
  /// overwriting the renderer selected by a newer widget configuration.
  void _replaceController(LinuxWebViewController oldController) {
    _attachmentGeneration += 1;
    _frameTimer?.cancel();
    _frameTimer = null;
    final oldRenderer = _renderer;
    _renderer = null;
    if (oldRenderer != null) {
      try {
        oldRenderer.dismissContextMenu();
        oldRenderer.dismissOptionMenu();
      } catch (_) {
        // A page may have closed either native menu before widget replacement.
      }
      oldController.detachRenderer(oldRenderer, this);
    }
    _error = null;
    _requestedSize = null;
    _requestedScale = null;
    _pressedButtons = 0;
    _clickCounter.reset();
    _navigationSwipe.cancel();
    _trackpadDidScroll = false;
    final hadOpenMenu = _contextMenuOpen || _optionMenuOpen;
    _contextMenuOpen = false;
    _optionMenuOpen = false;
    if (hadOpenMenu) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(Navigator.of(context).maybePop());
      });
    }
    _accessibilityTree = null;
    _nativeInputMethodState = null;
    _closeTextInputConnection();
    _fullscreen = false;
    _fullscreenOverlayScheduled = false;
    final fullscreenOverlay = _fullscreenOverlay;
    _fullscreenOverlay = null;
    fullscreenOverlay?.remove();
    fullscreenOverlay?.dispose();
    final customCursorImage = _customCursorImage;
    _customCursorImage = null;
    _customCursor = null;
    _mouseCursor = SystemMouseCursors.basic;
    if (customCursorImage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        customCursorImage.dispose();
      });
    }
    unawaited(_attach(widget.controller, _attachmentGeneration));
  }

  Future<void> _attach(
    LinuxWebViewController controller,
    int generation,
  ) async {
    try {
      final renderer = await controller.attachRenderer(this);
      if (!mounted ||
          generation != _attachmentGeneration ||
          !identical(controller, widget.controller)) {
        controller.detachRenderer(renderer, this);
        return;
      }
      setState(() {
        _renderer = renderer;
        _error = null;
      });
      controller.setApplicationVisibility(
        renderer,
        visible: _applicationVisible,
      );
      _safeInput(
        () => renderer.setFocus(_applicationVisible && _surfaceFocused),
      );
      _frameTimer = Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _pump(),
      );
      _pump();
    } catch (error) {
      if (mounted &&
          generation == _attachmentGeneration &&
          identical(controller, widget.controller)) {
        setState(() => _error = error);
      }
    }
  }

  /// Starts or stops native tree polling with Flutter's semantics lifecycle.
  void _handleSemanticsEnabledChanged() {
    final enabled = SemanticsBinding.instance.semanticsEnabled;
    if (_semanticsEnabled == enabled) return;
    _semanticsEnabled = enabled;
    _nextAccessibilityPoll = DateTime.fromMillisecondsSinceEpoch(0);
    if (!enabled) _accessibilityTree = null;
    if (mounted) setState(() {});
    final renderer = _renderer;
    if (enabled && renderer != null) _pumpAccessibility(renderer);
  }

  /// Polls WebKit's native AT-SPI socket only while semantics are requested.
  void _pumpAccessibility(NativeFrameRenderer renderer) {
    if (!_semanticsEnabled) return;
    final now = DateTime.now();
    if (now.isBefore(_nextAccessibilityPoll)) return;
    _nextAccessibilityPoll = now.add(const Duration(milliseconds: 250));
    final nextTree = renderer.refreshAccessibilityTree();
    if (_accessibilityTree?.generation == nextTree.generation) return;
    if (mounted) setState(() => _accessibilityTree = nextTree);
  }

  /// Advances the native event loop and mirrors browser-owned UI state.
  ///
  /// WPE runs without a GTK widget, so Flutter periodically drives its GLib
  /// context. The same tick requests changed texture frames and imports native
  /// clipboard and context-menu state into Flutter.
  void _pump() {
    final renderer = _renderer;
    if (!mounted || renderer == null) return;
    try {
      renderer.pump();
      widget.controller.didReceiveNavigationPolicyRequests(
        renderer,
        renderer.takeNavigationPolicyRequests(),
      );
      widget.controller.didReceiveNavigationEvents(
        renderer.takeNavigationEvents(),
      );
      widget.controller.didReceiveJavaScriptMessages(
        renderer.takeJavaScriptMessages(),
      );
      widget.controller.didReceiveJavaScriptDialogRequests(
        renderer,
        renderer.takeJavaScriptDialogRequests(),
      );
      widget.controller.didReceiveFileChooserRequests(
        renderer,
        renderer.takeFileChooserRequests(),
      );
      widget.controller.didReceivePopupRequests(renderer.takePopupRequests());
      if (renderer.takeWindowCloseRequest()) {
        widget.controller.didReceiveWindowCloseRequest();
      }
      for (final fullscreen in renderer.takeFullscreenEvents()) {
        widget.controller.didChangeFullscreen(fullscreen);
        _setFullscreen(fullscreen);
      }
      widget.controller.didReceiveDownloadRequests(
        renderer,
        renderer.takeDownloadRequests(),
      );
      widget.controller.didReceiveDownloadEvents(renderer.takeDownloadEvents());
      widget.controller.didReceivePermissionRequests(
        renderer,
        renderer.takePermissionRequests(),
      );
      widget.controller.didReceiveNotifications(
        renderer,
        renderer.takeNotifications(),
      );
      widget.controller.didCloseNotifications(
        renderer.takeClosedNotificationIds(),
      );
      widget.controller.didReceiveHttpAuthRequests(
        renderer,
        renderer.takeHttpAuthRequests(),
      );
      widget.controller.didReceiveSslAuthErrors(
        renderer,
        renderer.takeSslAuthErrors(),
      );
      final clipboardText = renderer.syncChangedClipboardToSystem();
      if (clipboardText != null) {
        unawaited(Clipboard.setData(ClipboardData(text: clipboardText)));
      }
      final menu = renderer.takeContextMenu();
      if (menu != null) unawaited(_showContextMenu(menu));
      final optionMenu = renderer.takeOptionMenu();
      if (optionMenu != null) unawaited(_showOptionMenu(optionMenu));
      final inputMethodState = renderer.takeInputMethodState();
      if (inputMethodState != null) {
        _handleNativeInputMethodState(inputMethodState);
      }
      final cursor = renderer.takeCursor();
      if (cursor != null) _handleNativeCursor(cursor);
      _pumpAccessibility(renderer);
    } catch (error) {
      _frameTimer?.cancel();
      _frameTimer = null;
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _applicationVisible = _isVisibleLifecycleState(state);
    final renderer = _renderer;
    if (renderer == null) return;
    try {
      widget.controller.setApplicationVisibility(
        renderer,
        visible: _applicationVisible,
      );
      renderer.setFocus(_applicationVisible && _surfaceFocused);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  bool _isVisibleLifecycleState(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  @override
  void dispose() {
    _attachmentGeneration += 1;
    WidgetsBinding.instance.removeObserver(this);
    SemanticsBinding.instance.removeSemanticsEnabledListener(
      _handleSemanticsEnabledChanged,
    );
    _frameTimer?.cancel();
    _fullscreen = false;
    _fullscreenOverlayScheduled = false;
    final fullscreenOverlay = _fullscreenOverlay;
    _fullscreenOverlay = null;
    fullscreenOverlay?.remove();
    fullscreenOverlay?.dispose();
    _closeTextInputConnection();
    _customCursorImage?.dispose();
    _customCursorImage = null;
    _gestureRouter.dispose();
    _focusNode.dispose();
    final renderer = _renderer;
    if (renderer != null) widget.controller.detachRenderer(renderer, this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText('Linux WebView failed: $error'),
          ),
        ),
      );
    }
    final renderer = _renderer;
    if (renderer == null || renderer.textureId <= 0) {
      return const ColoredBox(
        color: Color(0xff10131d),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_fullscreen) {
      // The same texture and input surface are rendered by the root overlay.
      // Keeping this slot occupied preserves the surrounding layout without
      // mounting a second widget against the controller.
      return const ColoredBox(color: Colors.black);
    }

    return _buildInteractiveSurface(context, renderer);
  }

  Widget _buildInteractiveSurface(
    BuildContext context,
    NativeFrameRenderer renderer,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 1,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 1,
        );
        _scheduleResize(size, MediaQuery.devicePixelRatioOf(context));
        return Focus(
          focusNode: _focusNode,
          onFocusChange: (focused) {
            _surfaceFocused = focused;
            _safeInput(() => renderer.setFocus(focused));
            if (focused) {
              // Clipboard reads are intentionally limited to paste-capable
              // input paths below. Starting one for every focus transition can
              // finish after the activating click and overwrite a newer copy
              // produced by that click's page handler.
              final inputMethodState = _nativeInputMethodState;
              if (inputMethodState?.focused ?? false) {
                _openTextInputConnection(inputMethodState!);
              }
            } else {
              _closeTextInputConnection();
            }
          },
          onKeyEvent: _handleKeyEvent,
          child: MouseRegion(
            cursor: _mouseCursor,
            onEnter: _handlePointerEnter,
            onHover: _handlePointerHover,
            onExit: _handlePointerExit,
            child: Listener(
              key: _surfaceKey,
              behavior: HitTestBehavior.opaque,
              onPointerDown: _gestureRouter.addPointer,
              onPointerSignal: _handlePointerSignal,
              onPointerPanZoomStart: _gestureRouter.addPointerPanZoom,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.hardEdge,
                children: [
                  Texture(
                    textureId: renderer.textureId,
                    filterQuality: FilterQuality.none,
                  ),
                  if (_semanticsEnabled)
                    _buildAccessibilityOverlay(renderer, size),
                  if (_pointerInside && _customCursorImage != null)
                    _buildCustomCursor(renderer),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Draws a WebKit custom cursor above the texture while Flutter hides its
  /// system cursor. WPE dimensions and hotspots are physical pixels, so both
  /// are divided by the scale most recently applied to the native surface.
  Widget _buildCustomCursor(NativeFrameRenderer renderer) {
    final cursor = _customCursor!;
    final image = _customCursorImage!;
    return Positioned.fromRect(
      rect: logicalCustomCursorRect(
        cursor,
        _lastPointerPosition,
        renderer.deviceScaleFactor,
      ),
      child: IgnorePointer(
        child: RawImage(
          image: image,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.none,
        ),
      ),
    );
  }

  /// Builds Flutter semantics from WebKit's process-isolated AT-SPI tree.
  ///
  /// Nodes are deliberately non-painting and do not participate in pointer hit
  /// testing. Their rectangles make desktop screen-reader exploration line up
  /// with the texture while pointer input continues to reach the listener
  /// beneath them. Offscreen nodes become available after semantic scrolling
  /// updates WebKit and the next native snapshot arrives.
  Widget _buildAccessibilityOverlay(
    NativeFrameRenderer renderer,
    Size surfaceSize,
  ) {
    final tree = _accessibilityTree;
    if (tree == null || !tree.occupied) return const SizedBox.shrink();
    final surfaceBounds = Offset.zero & surfaceSize;
    final children = <Widget>[];
    for (final node in tree.nodes) {
      final child = _buildAccessibilityNode(
        renderer,
        tree,
        node,
        surfaceBounds,
      );
      if (child != null) children.add(child);
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'linux-webview-content',
      onScrollUp: () => _scrollAccessibilityDocument(renderer, 0, -1),
      onScrollDown: () => _scrollAccessibilityDocument(renderer, 0, 1),
      onScrollLeft: () => _scrollAccessibilityDocument(renderer, -1, 0),
      onScrollRight: () => _scrollAccessibilityDocument(renderer, 1, 0),
      child: Stack(clipBehavior: Clip.hardEdge, children: children),
    );
  }

  Widget? _buildAccessibilityNode(
    NativeFrameRenderer renderer,
    NativeAccessibilityTree tree,
    NativeAccessibilityNode node,
    Rect surfaceBounds,
  ) {
    if (!node.isShowing || node.bounds.isEmpty) return null;
    final bounds = node.bounds.intersect(surfaceBounds);
    if (bounds.isEmpty) return null;

    final role = node.role;
    final isTextField = accessibilityRoleIsTextField(role);
    final isCheckable = accessibilityRoleIsCheckable(role);
    final isToggle = role == 'toggle button';
    final isButton =
        role == 'button' ||
        role == 'push button' ||
        role == 'menu item' ||
        role == 'check menu item' ||
        role == 'radio menu item';
    final isLink = role == 'link';
    final isSlider = role == 'slider' || role == 'spin button';
    final isSelectable =
        node.hasState(NativeAccessibilityState.selectable) ||
        role == 'list item' ||
        role == 'page tab' ||
        role == 'tree item';
    final actionIndex = primaryAccessibilityActionIndex(node);
    final interactive =
        actionIndex != null ||
        isTextField ||
        isCheckable ||
        isButton ||
        isLink ||
        isSlider ||
        node.hasState(NativeAccessibilityState.focusable);

    var label = node.name.trim();
    final nativeValue = node.value.trim();
    if (label.isEmpty && !isTextField) label = nativeValue;
    if (label.isEmpty && interactive) label = role;
    if (label.isEmpty && node.description.isEmpty && nativeValue.isEmpty) {
      return null;
    }

    final isMixed =
        isCheckable && node.hasState(NativeAccessibilityState.indeterminate);
    final isChecked = node.hasState(NativeAccessibilityState.checked);
    final supportsExpanded =
        node.hasState(NativeAccessibilityState.expandable) ||
        node.hasState(NativeAccessibilityState.collapsed);
    final enabled = interactive
        ? node.hasState(NativeAccessibilityState.enabled) &&
              node.hasState(NativeAccessibilityState.sensitive)
        : null;

    return Positioned.fromRect(
      rect: bounds,
      child: Semantics(
        key: ValueKey<int>(node.index),
        container: true,
        explicitChildNodes: true,
        identifier: 'linux-webview-node-${node.index}',
        label: label,
        value: isTextField ? nativeValue : null,
        hint: node.description.trim().isEmpty ? null : node.description.trim(),
        sortKey: OrdinalSortKey(node.index.toDouble()),
        enabled: enabled,
        checked: isCheckable && !isToggle && !isMixed ? isChecked : null,
        mixed: isCheckable && !isToggle && isMixed ? true : null,
        toggled: isToggle ? isChecked : null,
        selected: isSelectable
            ? node.hasState(NativeAccessibilityState.selected)
            : null,
        button: isButton ? true : null,
        link: isLink ? true : null,
        header: role == 'heading' || role == 'header' ? true : null,
        textField: isTextField ? true : null,
        readOnly: isTextField
            ? node.hasState(NativeAccessibilityState.readOnly) ||
                  !node.hasState(NativeAccessibilityState.editable)
            : null,
        focused: node.hasState(NativeAccessibilityState.focusable)
            ? node.hasState(NativeAccessibilityState.focused)
            : null,
        obscured: role == 'password text' ? true : null,
        multiline: isTextField
            ? node.hasState(NativeAccessibilityState.multiline)
            : null,
        image: role == 'image' || role == 'icon' ? true : null,
        liveRegion: role == 'alert' || role == 'statusbar' ? true : null,
        expanded: supportsExpanded
            ? node.hasState(NativeAccessibilityState.expanded)
            : null,
        isRequired: node.hasState(NativeAccessibilityState.required)
            ? true
            : null,
        slider: isSlider ? true : null,
        validationResult: node.hasState(NativeAccessibilityState.invalidEntry)
            ? SemanticsValidationResult.invalid
            : SemanticsValidationResult.none,
        onTap: actionIndex == null
            ? null
            : () => _runAccessibilityOperation(
                'activating $role',
                () => renderer.performAccessibilityAction(
                  tree,
                  node,
                  actionIndex,
                ),
              ),
        onFocus: node.hasState(NativeAccessibilityState.focusable)
            ? () => _runAccessibilityOperation(
                'focusing $role',
                () => renderer.focusAccessibilityNode(tree, node),
              )
            : null,
        onSetText:
            isTextField && node.hasState(NativeAccessibilityState.editable)
            ? (text) => _runAccessibilityOperation(
                'editing $role',
                () => renderer.setAccessibilityText(tree, node, text),
              )
            : null,
        onSetSelection: isTextField
            ? (selection) => _runAccessibilityOperation(
                'selecting $role text',
                () => renderer.setAccessibilitySelection(
                  tree,
                  node,
                  utf16OffsetToAccessibilityOffset(
                    nativeValue,
                    selection.start,
                  ),
                  utf16OffsetToAccessibilityOffset(nativeValue, selection.end),
                ),
              )
            : null,
        onIncrease: isSlider
            ? () => _runAccessibilityOperation(
                'increasing $role',
                () => renderer.adjustAccessibilityValue(tree, node, 1),
              )
            : null,
        onDecrease: isSlider
            ? () => _runAccessibilityOperation(
                'decreasing $role',
                () => renderer.adjustAccessibilityValue(tree, node, -1),
              )
            : null,
        child: const SizedBox.expand(),
      ),
    );
  }

  /// Reports native action failures without tearing down the browser pump.
  void _runAccessibilityOperation(String description, void Function() action) {
    try {
      action();
      _nextAccessibilityPoll = DateTime.fromMillisecondsSinceEpoch(0);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription('while $description through semantics'),
        ),
      );
    }
  }

  /// Scrolls by one viewport in the direction of a semantics action.
  void _scrollAccessibilityDocument(
    NativeFrameRenderer renderer,
    int horizontalDirection,
    int verticalDirection,
  ) {
    unawaited(
      renderer
          .evaluateJavaScript(
            'window.scrollBy('
            'window.innerWidth * 0.8 * $horizontalDirection,'
            'window.innerHeight * 0.8 * $verticalDirection);',
          )
          .then<void>((_) {
            _nextAccessibilityPoll = DateTime.fromMillisecondsSinceEpoch(0);
          })
          .catchError((Object error, StackTrace stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'webview_flutter_linux',
                context: ErrorDescription(
                  'while scrolling web content through semantics',
                ),
              ),
            );
          }),
    );
  }

  /// Moves this state's sole texture surface into the root Flutter overlay.
  void _setFullscreen(bool fullscreen) {
    if (!mounted || _fullscreen == fullscreen) return;
    _fullscreen = fullscreen;
    _requestedSize = null;
    _requestedScale = null;
    if (!fullscreen) {
      _fullscreenOverlayScheduled = false;
      final overlay = _fullscreenOverlay;
      _fullscreenOverlay = null;
      overlay?.remove();
      overlay?.dispose();
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
      return;
    }

    setState(() {});
    if (_fullscreenOverlay != null || _fullscreenOverlayScheduled) return;
    _fullscreenOverlayScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fullscreenOverlayScheduled = false;
      if (!mounted || !_fullscreen || _fullscreenOverlay != null) return;
      final entry = OverlayEntry(builder: _buildFullscreenOverlay);
      _fullscreenOverlay = entry;
      Overlay.of(context, rootOverlay: true).insert(entry);
      _focusNode.requestFocus();
    });
  }

  Widget _buildFullscreenOverlay(BuildContext context) {
    final renderer = _renderer;
    if (!_fullscreen || renderer == null) return const SizedBox.shrink();
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(child: _buildInteractiveSurface(context, renderer)),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton.filledTonal(
                key: const ValueKey('linux-webview-exit-fullscreen'),
                tooltip: 'Exit fullscreen',
                onPressed: _requestExitFullscreen,
                icon: const Icon(Icons.fullscreen_exit),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Asks the active document to leave fullscreen without changing views.
  void _requestExitFullscreen() {
    final renderer = _renderer;
    if (renderer == null) return;
    unawaited(
      renderer
          .evaluateJavaScript(
            'if (document.fullscreenElement) document.exitFullscreen();',
          )
          .then<void>((_) {})
          .catchError((Object error, StackTrace stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'webview_flutter_linux',
                context: ErrorDescription('while leaving HTML fullscreen'),
              ),
            );
          }),
    );
  }

  /// Coalesces layout changes and applies them after the current build frame.
  void _scheduleResize(Size size, double scale) {
    if (_requestedSize == size && _requestedScale == scale) return;
    _requestedSize = size;
    _requestedScale = scale;
    if (_resizeScheduled) return;
    _resizeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resizeScheduled = false;
      final renderer = _renderer;
      final requested = _requestedSize;
      if (!mounted || renderer == null || requested == null) return;
      _safeInput(
        () => renderer.resizeSurface(
          logicalWidth: requested.width,
          logicalHeight: requested.height,
          deviceScaleFactor: _requestedScale ?? 1,
        ),
      );
    });
  }

  /// Applies a complete WebKit cursor snapshot to Flutter's pointer surface.
  void _handleNativeCursor(NativeBrowserCursor cursor) {
    final previousImage = _customCursorImage;
    switch (cursor) {
      case NativeNamedBrowserCursor(:final name):
        setState(() {
          _mouseCursor = flutterCursorForWpeName(name);
          _customCursor = null;
          _customCursorImage = null;
        });
      case NativeCustomBrowserCursor():
        final image = ui.decodeImageFromPixelsSync(
          cursor.pixels,
          cursor.width,
          cursor.height,
          ui.PixelFormat.bgra8888,
        );
        setState(() {
          _mouseCursor = SystemMouseCursors.none;
          _customCursor = cursor;
          _customCursorImage = image;
        });
    }
    if (previousImage != null &&
        !identical(previousImage, _customCursorImage)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previousImage.dispose();
      });
    }
  }

  /// Records the logical pointer location and repaints only when a Flutter-
  /// drawn custom cursor needs to move or change visibility.
  void _recordPointerPosition(Offset position, {bool? inside}) {
    final nextInside = inside ?? _pointerInside;
    final shouldRepaint =
        _customCursorImage != null &&
        (_lastPointerPosition != position || _pointerInside != nextInside);
    if (shouldRepaint && mounted) {
      setState(() {
        _lastPointerPosition = position;
        _pointerInside = nextInside;
      });
    } else {
      _lastPointerPosition = position;
      _pointerInside = nextInside;
    }
  }

  void _handlePointerEnter(PointerEnterEvent event) {
    _recordPointerPosition(event.localPosition, inside: true);
    final point = _surfacePoint(event.localPosition);
    _safeInput(
      () => _renderer?.sendMouseMove(
        x: point.$1,
        y: point.$2,
        modifiers: _modifiers(buttons: event.buttons),
        mouseEnter: true,
      ),
    );
  }

  void _handlePointerHover(PointerHoverEvent event) {
    _recordPointerPosition(event.localPosition, inside: true);
    final point = _surfacePoint(event.localPosition);
    _safeInput(
      () => _renderer?.sendMouseMove(
        x: point.$1,
        y: point.$2,
        modifiers: _modifiers(buttons: event.buttons),
      ),
    );
  }

  void _handlePointerExit(PointerExitEvent event) {
    _recordPointerPosition(event.localPosition, inside: false);
    final point = _surfacePoint(event.localPosition);
    _safeInput(
      () => _renderer?.sendMouseMove(
        x: point.$1,
        y: point.$2,
        modifiers: _modifiers(buttons: event.buttons),
        mouseLeave: true,
      ),
    );
  }

  /// Dispatches a complete arena-approved pointer sequence to WebKit.
  void _handleRoutedPointerEvent(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        _handlePointerDown(event);
      case PointerMoveEvent():
        _handlePointerMove(event);
      case PointerUpEvent():
        _handlePointerUp(event);
      case PointerCancelEvent():
        _handlePointerCancel(event);
      case PointerPanZoomStartEvent():
        _handlePointerPanZoomStart(event);
      case PointerPanZoomUpdateEvent():
        _handlePointerPanZoomUpdate(event);
      case PointerPanZoomEndEvent():
        _handlePointerPanZoomEnd(event);
      case _:
        break;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _focusNode.requestFocus();
    _recordPointerPosition(event.localPosition, inside: true);
    if (event.kind == PointerDeviceKind.touch) {
      _sendTouch(NativeTouchEventType.down, event.pointer, event.localPosition);
      return;
    }
    final changed = event.buttons & ~_pressedButtons;
    _pressedButtons = event.buttons;
    for (final action in wpeMouseHistoryActions(changed)) {
      _enqueueInput(
        () => switch (action) {
          WpeMouseHistoryAction.back => widget.controller.goBack(),
          WpeMouseHistoryAction.forward => widget.controller.goForward(),
        },
      );
    }
    _sendChangedButtons(
      changed,
      event.localPosition,
      mouseUp: false,
      timeStamp: event.timeStamp,
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _recordPointerPosition(event.localPosition, inside: true);
    if (event.kind == PointerDeviceKind.touch) {
      _sendTouch(NativeTouchEventType.move, event.pointer, event.localPosition);
      return;
    }
    final released = _pressedButtons & ~event.buttons;
    final pressed = event.buttons & ~_pressedButtons;
    if (released != 0) {
      _sendChangedButtons(released, event.localPosition, mouseUp: true);
    }
    if (pressed != 0) {
      _sendChangedButtons(
        pressed,
        event.localPosition,
        mouseUp: false,
        timeStamp: event.timeStamp,
      );
    }
    _pressedButtons = event.buttons;
    final point = _surfacePoint(event.localPosition);
    _safeInput(
      () => _renderer?.sendMouseMove(
        x: point.$1,
        y: point.$2,
        modifiers: _modifiers(buttons: event.buttons),
      ),
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    _recordPointerPosition(event.localPosition, inside: true);
    if (event.kind == PointerDeviceKind.touch) {
      _sendTouch(NativeTouchEventType.up, event.pointer, event.localPosition);
      return;
    }
    final released = _pressedButtons & ~event.buttons;
    _sendChangedButtons(released, event.localPosition, mouseUp: true);
    _pressedButtons = event.buttons;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _sendTouch(
        NativeTouchEventType.cancel,
        event.pointer,
        event.localPosition,
      );
      return;
    }
    _sendChangedButtons(_pressedButtons, _lastPointerPosition, mouseUp: true);
    _pressedButtons = 0;
    _clickCounter.reset();
  }

  /// Preserves Flutter's contact identity while forwarding touch to WebKit.
  void _sendTouch(
    NativeTouchEventType eventType,
    int pointer,
    Offset position,
  ) {
    final point = _surfacePoint(position);
    _safeInput(
      () => _renderer?.sendTouch(
        eventType: eventType,
        sequenceId: pointer & 0xffffffff,
        x: point.$1,
        y: point.$2,
        modifiers: _modifiers(buttons: _pressedButtons),
      ),
    );
  }

  /// Sends every changed Flutter button bit as a distinct browser event.
  void _sendChangedButtons(
    int buttons,
    Offset position, {
    required bool mouseUp,
    Duration? timeStamp,
  }) {
    final point = _surfacePoint(position);
    for (final entry in const <(int, int)>[
      (kPrimaryMouseButton, 0),
      (kMiddleMouseButton, 1),
      (kSecondaryMouseButton, 2),
    ]) {
      if (buttons & entry.$1 == 0) continue;
      final modifiers = _modifiers(buttons: _pressedButtons);
      final clickCount = mouseUp
          ? 1
          : _clickCounter.register(
              button: entry.$2,
              timeStamp: timeStamp ?? Duration.zero,
              position: position,
            );
      void send() => _safeInput(
        () => _renderer?.sendMouseButton(
          x: point.$1,
          y: point.$2,
          modifiers: modifiers,
          button: entry.$2,
          mouseUp: mouseUp,
          clickCount: clickCount,
        ),
      );

      _enqueueInput(() async {
        if (entry.$1 == kSecondaryMouseButton && !mouseUp) {
          await _syncSystemClipboardToBrowser();
        }
        send();
      });
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    registerWebViewPointerScroll(event, _handleResolvedPointerScroll);
  }

  void _handleResolvedPointerScroll(PointerScrollEvent event) {
    _recordPointerPosition(event.localPosition, inside: true);
    _sendScroll(
      position: event.localPosition,
      delta: _wheelScroll.add(wpeMouseWheelDelta(event.scrollDelta)),
    );
  }

  void _handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
    _focusNode.requestFocus();
    _recordPointerPosition(event.localPosition, inside: true);
    _trackpadDidScroll = false;
    _navigationSwipe.start(
      enabled: widget.controller.allowsBackForwardNavigationGestures,
      canGoBack: widget.controller.canGoBackNow,
      canGoForward: widget.controller.canGoForwardNow,
      viewportWidth: _requestedSize?.width ?? context.size?.width ?? 0,
    );
    final renderer = _renderer;
    if (renderer != null && widget.controller.zoomEnabled) {
      _safeInput(() => _panZoomStartZoom = renderer.zoomLevel);
    }
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _recordPointerPosition(event.localPosition, inside: true);

    // Pinch and rotation need dedicated browser gesture events. Treating their
    // incidental pan component as scrolling makes a zoom gesture drift.
    final isPinching = (event.scale - 1).abs() > 0.001;
    final isRotating = event.rotation.abs() > 0.001;
    if (isPinching) {
      _navigationSwipe.cancel();
      if (widget.controller.zoomEnabled) {
        _safeInput(
          () => _renderer?.setZoomLevel(_panZoomStartZoom * event.scale),
        );
      }
      return;
    }
    if (isRotating) {
      _navigationSwipe.cancel();
      return;
    }

    final navigation = _navigationSwipe.add(event.localPanDelta);
    if (navigation.claimsGesture) {
      if (_trackpadDidScroll) {
        _sendTrackpadScroll(
          position: event.localPosition,
          delta: Offset.zero,
          isStop: true,
        );
        _trackpadDidScroll = false;
      }
      return;
    }

    _sendTrackpadScroll(
      position: event.localPosition,
      delta: wpeTrackpadPanDelta(event.localPanDelta),
    );
  }

  void _handlePointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _recordPointerPosition(event.localPosition, inside: true);
    if (_trackpadDidScroll) {
      _sendTrackpadScroll(
        position: event.localPosition,
        delta: Offset.zero,
        isStop: true,
      );
    }
    _trackpadDidScroll = false;
    final navigation = _navigationSwipe.end();
    if (navigation != null) {
      _enqueueInput(() async {
        switch (navigation) {
          case WpeNavigationSwipeDirection.back:
            if (await widget.controller.canGoBack()) {
              await widget.controller.goBack();
            }
          case WpeNavigationSwipeDirection.forward:
            if (await widget.controller.canGoForward()) {
              await widget.controller.goForward();
            }
        }
      });
    }
  }

  /// Forwards a precise touchpad stream and its explicit terminating event.
  void _sendTrackpadScroll({
    required Offset position,
    required Offset delta,
    bool isStop = false,
  }) {
    if (!isStop && delta == Offset.zero) return;
    final point = _surfacePoint(position);
    _safeInput(
      () => _renderer?.sendTrackpadScroll(
        x: point.$1,
        y: point.$2,
        modifiers: _modifiers(buttons: _pressedButtons),
        deltaX: delta.dx,
        deltaY: delta.dy,
        isStop: isStop,
      ),
    );
    if (!isStop) _trackpadDidScroll = true;
  }

  /// Forwards an integral scroll delta at the current Flutter surface point.
  void _sendScroll({required Offset position, required (int, int) delta}) {
    if (delta == (0, 0)) return;
    final point = _surfacePoint(position);
    _safeInput(
      () => _renderer?.sendMouseWheel(
        x: point.$1,
        y: point.$2,
        modifiers: _modifiers(buttons: _pressedButtons),
        deltaX: delta.$1,
        deltaY: delta.$2,
      ),
    );
  }

  /// Synchronizes browser-owned editor state into Flutter's platform IME.
  ///
  /// WebKit reports complete surrounding state after pointer selection,
  /// navigation keys, script-driven focus, and committed edits. An active
  /// Flutter composition remains authoritative until it is committed or
  /// cancelled; replacing it with an intermediate browser callback would make
  /// multi-key IMEs lose their marked range.
  void _handleNativeInputMethodState(
    NativeBrowserInputMethodState inputMethodState,
  ) {
    _nativeInputMethodState = inputMethodState;
    if (!inputMethodState.focused || !_surfaceFocused) {
      _closeTextInputConnection();
      return;
    }
    _openTextInputConnection(inputMethodState);
    final composing = _editingValue.composing;
    if (!composing.isValid || composing.isCollapsed) {
      _editingValue = inputMethodState.editingValue;
      _textInputConnection?.setEditingState(_editingValue);
    }
    _updateTextInputGeometry(inputMethodState);
  }

  /// Opens one platform text-input connection for the focused HTML editor.
  void _openTextInputConnection(
    NativeBrowserInputMethodState inputMethodState,
  ) {
    final current = _textInputConnection;
    if (current?.attached ?? false) {
      _updateTextInputGeometry(inputMethodState);
      return;
    }
    current?.close();
    _editingValue = inputMethodState.editingValue;
    final connection = TextInput.attach(
      this,
      TextInputConfiguration(
        viewId: View.of(context).viewId,
        inputType: _textInputType(inputMethodState.inputPurpose),
        obscureText: inputMethodState.inputPurpose == 6,
        autocorrect: inputMethodState.inputHints & 1 != 0,
        enableSuggestions: inputMethodState.inputPurpose != 6,
        inputAction: TextInputAction.done,
      ),
    );
    _textInputConnection = connection;
    connection.setEditingState(_editingValue);
    _updateTextInputGeometry(inputMethodState);
    connection.show();
  }

  void _closeTextInputConnection() {
    final connection = _textInputConnection;
    _textInputConnection = null;
    connection?.close();
    _editingValue = TextEditingValue.empty;
  }

  /// Positions system candidate UI at WebKit's caret inside the texture.
  void _updateTextInputGeometry(
    NativeBrowserInputMethodState inputMethodState,
  ) {
    final connection = _textInputConnection;
    final surfaceBox =
        _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (connection == null || !connection.attached || surfaceBox == null) {
      return;
    }
    connection.setEditableSizeAndTransform(
      surfaceBox.size,
      surfaceBox.getTransformTo(null),
    );
    connection.setComposingRect(inputMethodState.caretRect);
    connection.setCaretRect(inputMethodState.caretRect);
  }

  TextInputType _textInputType(int purpose) => switch (purpose) {
    1 => TextInputType.number,
    2 => const TextInputType.numberWithOptions(decimal: true, signed: true),
    3 => TextInputType.phone,
    4 => TextInputType.url,
    5 => TextInputType.emailAddress,
    6 => TextInputType.visiblePassword,
    _ => TextInputType.text,
  };

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_fullscreen && event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is! KeyUpEvent) _requestExitFullscreen();
      return KeyEventResult.handled;
    }
    final windowsKeyCode = webViewWindowsKeyCode(event.logicalKey);
    if (windowsKeyCode == null) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final modifiers = webViewKeyboardModifiers(
      shift: keyboard.isShiftPressed,
      control: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
      capsLock: keyboard.lockModesEnabled.contains(KeyboardLockMode.capsLock),
      numLock: keyboard.lockModesEnabled.contains(KeyboardLockMode.numLock),
    );
    final character = event.character;
    final textInputActive = _textInputConnection?.attached ?? false;
    final hasCommandModifier =
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed;
    if (textInputActive && !hasCommandModifier && _isPrintableText(character)) {
      // Flutter's Linux text-input plugin has already offered this key to the
      // system IME. Forwarding it as a raw WPE key as well would insert plain
      // characters twice and bypass dead-key composition.
      return KeyEventResult.handled;
    }
    final characterCode = character == null || character.isEmpty
        ? 0
        : character.runes.first;
    final isPaste =
        event is! KeyUpEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (keyboard.isControlPressed || keyboard.isMetaPressed);

    _enqueueInput(() async {
      if (isPaste) await _syncSystemClipboardToBrowser();
      _renderer?.sendKey(
        eventType: event is KeyUpEvent
            ? webViewKeyEventKeyUp
            : webViewKeyEventRawKeyDown,
        modifiers: modifiers,
        windowsKeyCode: windowsKeyCode,
        nativeKeyCode: event.physicalKey.usbHidUsage,
        character: characterCode,
        unmodifiedCharacter: characterCode,
      );
    });
    return KeyEventResult.handled;
  }

  bool _isPrintableText(String? character) =>
      character != null &&
      character.isNotEmpty &&
      character.runes.every((rune) => rune >= 0x20 && rune != 0x7f);

  @override
  TextEditingValue get currentTextEditingValue => _editingValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  /// Receives semantic edits produced by Flutter's system IME connection.
  ///
  /// The previous and next full editing models are reduced to the native
  /// preedit/commit/delete operations expected by WebKit. Raw character key
  /// events are deliberately excluded from this path by [_handleKeyEvent].
  @override
  void updateEditingValue(TextEditingValue value) {
    final inputMethodState = _nativeInputMethodState;
    final renderer = _renderer;
    if (renderer == null || !(inputMethodState?.focused ?? false)) return;
    final previous = _editingValue;
    final commands = browserTextInputCommands(previous, value);
    _editingValue = value;
    if (commands.isEmpty &&
        previous.text == value.text &&
        previous.selection != value.selection) {
      _sendBoundarySelection(value);
      return;
    }
    _safeInput(() {
      for (final command in commands) {
        switch (command) {
          case BrowserSetPreedit(:final text, :final cursorOffset):
            renderer.setInputMethodPreedit(text, cursorOffset);
          case BrowserCommitText(:final text):
            renderer.commitInputMethodText(text);
          case BrowserDeleteSurrounding(:final offset, :final characterCount):
            renderer.deleteInputMethodSurrounding(offset, characterCount);
          case BrowserCancelPreedit():
            renderer.cancelInputMethodPreedit();
        }
      }
    });
  }

  /// Replays Home/End selection changes consumed by Flutter's Linux text model.
  ///
  /// The embedder handles these two keys before the framework receives a raw
  /// event. WebKit still needs the corresponding native key to update its DOM
  /// selection; arbitrary selection changes continue to originate in WebKit.
  void _sendBoundarySelection(TextEditingValue value) {
    if (!value.selection.isValid) return;
    if (value.selection.extentOffset == 0) {
      _sendSyntheticKey(
        LogicalKeyboardKey.home,
        PhysicalKeyboardKey.home,
        shift: !value.selection.isCollapsed,
      );
    } else if (value.selection.extentOffset == value.text.length) {
      _sendSyntheticKey(
        LogicalKeyboardKey.end,
        PhysicalKeyboardKey.end,
        shift: !value.selection.isCollapsed,
      );
    }
  }

  void _sendSyntheticKey(
    LogicalKeyboardKey logicalKey,
    PhysicalKeyboardKey physicalKey, {
    bool shift = false,
    bool control = false,
  }) {
    final renderer = _renderer;
    final windowsKeyCode = webViewWindowsKeyCode(logicalKey);
    if (renderer == null || windowsKeyCode == null) return;
    final modifiers = webViewKeyboardModifiers(
      shift: shift,
      control: control,
      alt: false,
      meta: false,
      capsLock: false,
      numLock: false,
    );
    for (final eventType in const <int>[
      webViewKeyEventRawKeyDown,
      webViewKeyEventKeyUp,
    ]) {
      renderer.sendKey(
        eventType: eventType,
        modifiers: modifiers,
        windowsKeyCode: windowsKeyCode,
        nativeKeyCode: physicalKey.usbHidUsage,
      );
    }
  }

  @override
  void performAction(TextInputAction action) {
    _sendSyntheticKey(LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter);
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  bool onFocusReceived() {
    _focusNode.requestFocus();
    return true;
  }

  @override
  void connectionClosed() {
    _textInputConnection = null;
  }

  Future<void> _syncSystemClipboardToBrowser() async {
    final renderer = _renderer;
    if (renderer == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    // Clipboard reads leave this isolate and can complete after unmount or a
    // controller replacement. Revalidate the attachment before starting the
    // native import so a stale focus request cannot touch a disposed renderer.
    if (!mounted || !identical(renderer, _renderer)) return;
    _lastSystemClipboardText = data?.text;
    final imported = await renderer.importSystemClipboard(
      plainTextOverride: data?.text,
    );
    if (!mounted || !identical(renderer, _renderer)) return;
    if (imported) return;
    renderer.setClipboardText(data?.text ?? '');
  }

  /// Serializes input that depends on asynchronous clipboard synchronization.
  ///
  /// In particular, paste shortcuts and secondary-button presses must update
  /// the browser clipboard before WPE receives the triggering event.
  void _enqueueInput(Future<void> Function() action) {
    _inputQueue = _inputQueue.then((_) => action()).catchError((Object error) {
      if (mounted) setState(() => _error = error);
    });
  }

  void _safeInput(void Function() action) {
    try {
      action();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// Converts a logical local position into a bounded WPE surface coordinate.
  (int, int) _surfacePoint(Offset position) {
    final size = _requestedSize;
    final maxX = size == null ? 16383 : (size.width.ceil() - 1).clamp(0, 16383);
    final maxY = size == null
        ? 16383
        : (size.height.ceil() - 1).clamp(0, 16383);
    return (
      position.dx.round().clamp(0, maxX),
      position.dy.round().clamp(0, maxY),
    );
  }

  int _modifiers({required int buttons}) {
    final keyboard = HardwareKeyboard.instance;
    return webViewKeyboardModifiers(
          shift: keyboard.isShiftPressed,
          control: keyboard.isControlPressed,
          alt: keyboard.isAltPressed,
          meta: keyboard.isMetaPressed,
          capsLock: keyboard.lockModesEnabled.contains(
            KeyboardLockMode.capsLock,
          ),
          numLock: keyboard.lockModesEnabled.contains(KeyboardLockMode.numLock),
        ) |
        (buttons & kPrimaryMouseButton != 0
            ? webViewEventFlagLeftMouseButton
            : 0) |
        (buttons & kMiddleMouseButton != 0
            ? webViewEventFlagMiddleMouseButton
            : 0) |
        (buttons & kSecondaryMouseButton != 0
            ? webViewEventFlagRightMouseButton
            : 0);
  }

  /// Presents WPE's menu model using Flutter widgets and returns the selection.
  Future<void> _showContextMenu(NativeBrowserContextMenu menu) async {
    final rendererAtOpen = _renderer;
    if (_contextMenuOpen || !mounted || menu.items.isEmpty) {
      rendererAtOpen?.dismissContextMenu();
      return;
    }
    final surfaceBox =
        _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (surfaceBox == null || overlayBox == null) {
      rendererAtOpen?.dismissContextMenu();
      return;
    }
    final global = surfaceBox.localToGlobal(
      menu.position,
      ancestor: overlayBox,
    );
    _contextMenuOpen = true;
    final entries = <PopupMenuEntry<int>>[];
    for (final item in menu.items) {
      if (item.isSeparator) {
        entries.add(const PopupMenuDivider());
      } else {
        entries.add(
          PopupMenuItem<int>(
            value: item.index,
            enabled: item.isEnabled,
            child: Text(item.title),
          ),
        );
      }
    }
    int? selected;
    try {
      selected = await showMenu<int>(
        context: context,
        position: RelativeRect.fromLTRB(
          global.dx,
          global.dy,
          overlayBox.size.width - global.dx,
          overlayBox.size.height - global.dy,
        ),
        items: entries,
      );
    } finally {
      _contextMenuOpen = false;
    }
    if (!mounted || !identical(rendererAtOpen, _renderer)) return;
    if (selected == null) {
      rendererAtOpen?.dismissContextMenu();
    } else {
      // Flutter's popup route temporarily moves focus away from the texture.
      // WebKit editing commands such as Paste are no-ops while the headless
      // view is unfocused, and route focus restoration occurs after the menu
      // future completes. Restore both sides before activating the retained
      // browser action.
      _focusNode.requestFocus();
      rendererAtOpen?.setFocus(true);
      final item = menu.items.firstWhere((item) => item.index == selected);
      switch (item.stockAction) {
        case _contextMenuActionCopy:
          final selectedText = await _selectedBrowserText(rendererAtOpen);
          if (selectedText == null) {
            _sendSyntheticKey(
              LogicalKeyboardKey.keyC,
              PhysicalKeyboardKey.keyC,
              control: true,
            );
          } else {
            rendererAtOpen?.setClipboardText(selectedText);
            await Clipboard.setData(ClipboardData(text: selectedText));
          }
          rendererAtOpen?.dismissContextMenu();
        case _contextMenuActionCut:
          final selectedText = await _selectedBrowserText(rendererAtOpen);
          if (selectedText == null) {
            _sendSyntheticKey(
              LogicalKeyboardKey.keyX,
              PhysicalKeyboardKey.keyX,
              control: true,
            );
          } else {
            rendererAtOpen
              ?..setClipboardText(selectedText)
              ..commitInputMethodText('');
          }
          rendererAtOpen?.dismissContextMenu();
        case _contextMenuActionPaste:
          final text = _lastSystemClipboardText;
          if (text == null) {
            // Rich-only selections retain WebKit's shortcut path because
            // Flutter has no plain-text value to commit through the input
            // method bridge.
            _sendSyntheticKey(
              LogicalKeyboardKey.keyV,
              PhysicalKeyboardKey.keyV,
              control: true,
            );
          } else {
            rendererAtOpen?.commitInputMethodText(text);
          }
          rendererAtOpen?.dismissContextMenu();
        default:
          rendererAtOpen?.activateContextMenuItem(selected);
      }
    }
  }

  String? _selectedInputMethodText() {
    final state = _nativeInputMethodState;
    if (state == null || !state.focused || !state.selection.isValid) {
      return null;
    }
    final selection = state.selection;
    if (selection.isCollapsed ||
        selection.start < 0 ||
        selection.end > state.text.length) {
      return null;
    }
    return selection.textInside(state.text);
  }

  Future<String?> _selectedBrowserText(NativeFrameRenderer? renderer) async {
    final nativeText = _selectedInputMethodText();
    if (nativeText != null) return nativeText;
    if (renderer == null) return null;
    try {
      final result = await renderer.evaluateJavaScript(r'''
        (() => {
          const active = document.activeElement;
          if (active instanceof HTMLInputElement ||
              active instanceof HTMLTextAreaElement) {
            const start = active.selectionStart;
            const end = active.selectionEnd;
            if (start !== null && end !== null && start !== end) {
              return active.value.substring(start, end);
            }
          }
          const selection = window.getSelection();
          return selection && !selection.isCollapsed
            ? selection.toString()
            : null;
        })()
      ''');
      return result is String && result.isNotEmpty ? result : null;
    } catch (_) {
      return null;
    }
  }

  /// Presents an HTML `<select>` model using Flutter popup-menu widgets.
  ///
  /// WebKit retains the native menu while Flutter is visible. Every exit path
  /// activates one enabled option or explicitly closes the native menu, so the
  /// page never remains suspended waiting for toolkit UI.
  Future<void> _showOptionMenu(NativeBrowserOptionMenu menu) async {
    final rendererAtOpen = _renderer;
    if (_optionMenuOpen || !mounted || menu.items.isEmpty) {
      rendererAtOpen?.dismissOptionMenu();
      return;
    }
    final surfaceBox =
        _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (surfaceBox == null || overlayBox == null) {
      rendererAtOpen?.dismissOptionMenu();
      return;
    }
    final global = surfaceBox.localToGlobal(
      menu.bounds.bottomLeft,
      ancestor: overlayBox,
    );
    final entries = <PopupMenuEntry<int>>[
      for (final item in menu.items)
        PopupMenuItem<int>(
          value: item.index,
          enabled: item.isEnabled && !item.isGroupLabel,
          child: Tooltip(
            message: item.tooltip ?? '',
            child: Padding(
              padding: EdgeInsets.only(left: item.isGroupChild ? 20 : 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    child: item.isSelected
                        ? const Icon(Icons.check, size: 18)
                        : null,
                  ),
                  Flexible(
                    child: Text(
                      item.label,
                      style: item.isGroupLabel
                          ? const TextStyle(fontWeight: FontWeight.bold)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];

    _optionMenuOpen = true;
    int? selected;
    try {
      selected = await showMenu<int>(
        context: context,
        position: RelativeRect.fromLTRB(
          global.dx,
          global.dy,
          (overlayBox.size.width - global.dx - menu.bounds.width).clamp(
            0,
            double.infinity,
          ),
          (overlayBox.size.height - global.dy).clamp(0, double.infinity),
        ),
        items: entries,
      );
    } finally {
      _optionMenuOpen = false;
    }
    if (!mounted || !identical(rendererAtOpen, _renderer)) return;
    try {
      if (selected == null) {
        rendererAtOpen?.dismissOptionMenu();
      } else {
        rendererAtOpen?.activateOptionMenuItem(selected);
      }
    } catch (error, stackTrace) {
      // The page may remove the select element while Flutter's popup is open.
      // Native close wins that race; it is not a renderer-fatal condition.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'webview_flutter_linux',
          context: ErrorDescription('while resolving an HTML option menu'),
        ),
      );
    }
  }
}
