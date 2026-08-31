// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Selects a local destination for a browser-initiated download.
///
/// Return null to cancel. The callback may await Flutter UI such as a file
/// picker because WPE pauses the transfer until a destination is supplied.
typedef LinuxWebViewDownloadDestinationCallback =
    Future<LinuxWebViewDownloadDestination?> Function(
      LinuxWebViewDownloadRequest request,
    );

/// Receives created, progress, failure, and completion download transitions.
typedef LinuxWebViewDownloadEventCallback =
    void Function(LinuxWebViewDownloadEvent event);

/// Metadata supplied when page content initiates a download.
final class LinuxWebViewDownloadRequest {
  /// Creates an immutable browser download request.
  const LinuxWebViewDownloadRequest({
    required this.id,
    required this.url,
    required this.suggestedFilename,
    required this.mimeType,
    required this.contentLength,
  });

  /// Stable identifier used to correlate later lifecycle events.
  final int id;

  /// Resource URL requested by the page.
  final String url;

  /// Filename proposed by the response, or an empty string if unavailable.
  final String suggestedFilename;

  /// Response MIME type, or null if WebKit could not determine one.
  final String? mimeType;

  /// Expected response bytes, or null if the server omitted the size.
  final int? contentLength;
}

/// A filesystem destination selected by the Flutter application.
final class LinuxWebViewDownloadDestination {
  /// Creates a destination at [path].
  ///
  /// Existing files are protected by default. Set [allowOverwrite] explicitly
  /// when replacement is intended.
  const LinuxWebViewDownloadDestination(
    this.path, {
    this.allowOverwrite = false,
  });

  /// Absolute filesystem path, or a `file:` URI, for the downloaded file.
  final String path;

  /// Whether WebKit may replace an existing destination file.
  final bool allowOverwrite;
}

/// Observable states in a WPE download lifecycle.
enum LinuxWebViewDownloadEventKind {
  /// The selected destination file was created successfully.
  createdDestination,

  /// Additional response data was written to the destination.
  progress,

  /// The transfer failed or was cancelled.
  failed,

  /// The transfer ended, following [failed] when unsuccessful.
  finished,
}

/// One lifecycle snapshot for a browser-initiated download.
final class LinuxWebViewDownloadEvent {
  /// Creates an immutable download lifecycle event.
  const LinuxWebViewDownloadEvent({
    required this.id,
    required this.kind,
    required this.receivedBytes,
    required this.contentLength,
    required this.destination,
    required this.errorCode,
    required this.errorDescription,
  });

  /// Stable identifier from [LinuxWebViewDownloadRequest.id].
  final int id;

  /// Created, progress, failed, or finished transition.
  final LinuxWebViewDownloadEventKind kind;

  /// Total bytes written at the time of this event.
  final int receivedBytes;

  /// Expected response bytes, or null when unknown.
  final int? contentLength;

  /// Absolute local destination after WebKit creates it, when available.
  final String? destination;

  /// WPE download error code for failed events, otherwise zero.
  final int errorCode;

  /// Human-readable native failure detail, when available.
  final String? errorDescription;

  /// Completed fraction in the inclusive range zero through one.
  ///
  /// Returns null when the response length is unknown or zero.
  double? get progress {
    final length = contentLength;
    if (length == null || length <= 0) return null;
    return (receivedBytes / length).clamp(0.0, 1.0);
  }
}
