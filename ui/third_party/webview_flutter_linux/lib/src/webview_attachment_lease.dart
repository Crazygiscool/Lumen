// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Enforces the one-widget-at-a-time ownership contract for a native WebView.
///
/// The controller deliberately retains its renderer while no widget is
/// mounted so browser history and document state survive a temporary removal
/// from the Flutter tree. A lease prevents two independently mounted widget
/// states from pumping and sending input to that retained renderer at once.
final class WebViewAttachmentLease {
  Object? _owner;

  /// Whether any widget currently owns the rendering/input attachment.
  bool get isAttached => _owner != null;

  /// Claims the attachment for [owner].
  ///
  /// Reclaiming with the identical owner is idempotent, which makes an async
  /// attachment completion safe. A different owner indicates that one
  /// controller was mounted in two widget locations and is rejected before
  /// either surface can race the native texture.
  void acquire(Object owner) {
    final current = _owner;
    if (current != null && !identical(current, owner)) {
      throw StateError(
        'A LinuxWebViewController can only be attached to one '
        'WebViewWidget at a time.',
      );
    }
    _owner = owner;
  }

  /// Releases the lease only when [owner] is the current holder.
  ///
  /// Returning false lets a stale widget teardown remain a harmless no-op
  /// after ownership has moved elsewhere.
  bool release(Object owner) {
    if (!identical(_owner, owner)) return false;
    _owner = null;
    return true;
  }

  /// Clears any owner during explicit controller or popup disposal.
  void clear() => _owner = null;
}
