// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Raw Dart FFI declarations for the versioned Rust WebView ABI.
///
/// These declarations intentionally mirror the exported Rust signatures. A
/// zero status indicates success, positive statuses are operation-specific,
/// and negative statuses indicate failure. Except for API discovery and view
/// creation, every operation is scoped by an opaque native view handle.
library;

import 'dart:ffi' as ffi;

/// Returns the version of the Rust bridge's exported ABI.
@ffi.Native<ffi.Uint32 Function()>(symbol: 'webview_flutter_linux_api_version')
external int webviewFlutterLinuxApiVersion();

/// Installs compiled ad-block rules for the web-process extension.
///
/// [bytes] and [length] describe the rule blob; the native side copies it
/// atomically into the shared extension directory. Returns 0 on success.
@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Size)>(symbol: 'webview_flutter_linux_set_content_block_rules')
external int webviewFlutterLinuxSetContentBlockRules(
  ffi.Pointer<ffi.Uint8> bytes,
  int length,
);

/// Returns and drains the ad-blocked request count for the view [handle].
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(symbol: 'webview_flutter_linux_take_blocked_count')
external int webviewFlutterLinuxTakeBlockedCount(int handle);

/// Creates a native view for [engineHandle] and writes its handle to
/// [outputHandle].
///
/// [initialUrl] must point to a null-terminated UTF-8 string. The returned
/// handle scopes every subsequent texture and WPE operation.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Int64,
    ffi.Pointer<ffi.Char>,
    ffi.Int32,
    ffi.Int32,
    ffi.Int32,
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Uint64>,
  )
>(symbol: 'webview_flutter_linux_view_create')
external int webviewFlutterLinuxViewCreate(
  int engineHandle,
  ffi.Pointer<ffi.Char> initialUrl,
  int javaScriptEnabled,
  int javaScriptCanOpenWindowsAutomatically,
  int javaScriptCanAccessClipboard,
  ffi.Pointer<ffi.Char> userAgent,
  ffi.Pointer<ffi.Uint64> outputHandle,
);

/// Releases the native view identified by [handle].
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_view_dispose',
)
external int webviewFlutterLinuxViewDispose(int handle);

/// Schedules platform-thread disposal for a finalizer-owned native [handle].
///
/// The pointer value encodes the non-zero integer handle. Unlike the ordinary
/// dispose entry point, this callback may be invoked from a Dart finalizer
/// thread and therefore only attaches teardown work to GLib's main context.
@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'webview_flutter_linux_view_dispose_finalizer',
)
external void webviewFlutterLinuxViewDisposeFinalizer(
  ffi.Pointer<ffi.Void> handle,
);

/// Returns the Flutter external-texture identifier for [handle].
@ffi.Native<ffi.Int64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_id',
)
external int webviewFlutterLinuxTextureId(int handle);

/// Returns the latest texture width in physical pixels.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_width',
)
external int webviewFlutterLinuxTextureWidth(int handle);

/// Returns the latest texture height in physical pixels.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_height',
)
external int webviewFlutterLinuxTextureHeight(int handle);

/// Returns a counter that changes when the native texture content changes.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_generation',
)
external int webviewFlutterLinuxTextureGeneration(int handle);

/// Notifies Flutter that a new frame is available for [handle]'s texture.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_request_frame',
)
external int webviewFlutterLinuxTextureRequestFrame(int handle);

/// Returns the number of DMA-BUF frames copied into fallback storage.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_texture_dma_buf_copy_count',
)
external int webviewFlutterLinuxTextureDmaBufCopyCount(int handle);

/// Returns a counter that changes when WebKit resolves a different cursor.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_cursor_generation',
)
external int webviewFlutterLinuxWpeCursorGeneration(int handle);

/// Returns `1` for a named cursor and `2` for custom cursor pixels.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_cursor_kind',
)
external int webviewFlutterLinuxWpeCursorKind(int handle);

/// Returns the UTF-8 byte length of WebKit's current named cursor.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_cursor_name_length',
)
external int webviewFlutterLinuxWpeCursorNameLength(int handle);

/// Copies WebKit's current named cursor into caller-owned storage.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_cursor_copy_name',
)
external int webviewFlutterLinuxWpeCursorCopyName(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Returns the custom cursor width in physical pixels.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_cursor_width',
)
external int webviewFlutterLinuxWpeCursorWidth(int handle);

/// Returns the custom cursor height in physical pixels.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_cursor_height',
)
external int webviewFlutterLinuxWpeCursorHeight(int handle);

/// Returns the custom cursor hotspot X coordinate in physical pixels.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_cursor_hotspot_x',
)
external int webviewFlutterLinuxWpeCursorHotspotX(int handle);

/// Returns the custom cursor hotspot Y coordinate in physical pixels.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_cursor_hotspot_y',
)
external int webviewFlutterLinuxWpeCursorHotspotY(int handle);

/// Returns the tightly packed custom cursor byte length.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_cursor_pixels_length',
)
external int webviewFlutterLinuxWpeCursorPixelsLength(int handle);

/// Copies tightly packed premultiplied ARGB8888 custom cursor pixels.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_cursor_copy_pixels',
)
external int webviewFlutterLinuxWpeCursorCopyPixels(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Runs pending GLib and WPE work for one non-blocking iteration.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_pump',
)
external int webviewFlutterLinuxWpePump(int handle);

/// Returns one when WebKit's native history has a previous item.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_can_go_back',
)
external int webviewFlutterLinuxWpeCanGoBack(int handle);

/// Returns one when WebKit's native history has a following item.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_can_go_forward',
)
external int webviewFlutterLinuxWpeCanGoForward(int handle);

/// Traverses to the previous native history item.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_go_back',
)
external int webviewFlutterLinuxWpeGoBack(int handle);

/// Traverses to the following native history item.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_go_forward',
)
external int webviewFlutterLinuxWpeGoForward(int handle);

/// Reloads WebKit's current native history item.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_reload',
)
external int webviewFlutterLinuxWpeReload(int handle);

/// Navigates [handle] to the null-terminated UTF-8 [url].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_navigate',
)
external int webviewFlutterLinuxWpeNavigate(
  int handle,
  ffi.Pointer<ffi.Char> url,
);

/// Loads UTF-8 [content] with an optional WebKit [baseUri].
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)
>(symbol: 'webview_flutter_linux_wpe_load_html')
external int webviewFlutterLinuxWpeLoadHtml(
  int handle,
  ffi.Pointer<ffi.Char> content,
  ffi.Pointer<ffi.Char> baseUri,
);

/// Navigates with parallel null-terminated HTTP header name/value arrays.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Pointer<ffi.Char>>,
    ffi.Pointer<ffi.Pointer<ffi.Char>>,
    ffi.Size,
  )
>(symbol: 'webview_flutter_linux_wpe_navigate_with_headers')
external int webviewFlutterLinuxWpeNavigateWithHeaders(
  int handle,
  ffi.Pointer<ffi.Char> url,
  ffi.Pointer<ffi.Pointer<ffi.Char>> headerNames,
  ffi.Pointer<ffi.Pointer<ffi.Char>> headerValues,
  int headerCount,
);

/// Navigates with POST, application-supplied headers, and a binary body.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Pointer<ffi.Char>>,
    ffi.Pointer<ffi.Pointer<ffi.Char>>,
    ffi.Size,
    ffi.Pointer<ffi.Uint8>,
    ffi.Size,
  )
>(symbol: 'webview_flutter_linux_wpe_navigate_post')
external int webviewFlutterLinuxWpeNavigatePost(
  int handle,
  ffi.Pointer<ffi.Char> url,
  ffi.Pointer<ffi.Pointer<ffi.Char>> headerNames,
  ffi.Pointer<ffi.Pointer<ffi.Char>> headerValues,
  int headerCount,
  ffi.Pointer<ffi.Uint8> body,
  int bodyLength,
);

/// Starts asynchronous JavaScript evaluation for [requestId].
///
/// Completion is retrieved from the per-view JavaScript result queue.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_evaluate_javascript',
)
external int webviewFlutterLinuxWpeEvaluateJavaScript(
  int handle,
  int requestId,
  ffi.Pointer<ffi.Char> script,
);

/// Starts an application-wide website-data clear for [requestId].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_website_data_clear',
)
external int webviewFlutterLinuxWebsiteDataClear(int requestId, int types);

/// Returns the number of completed global website-data operations.
@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'webview_flutter_linux_website_data_result_count',
)
external int webviewFlutterLinuxWebsiteDataResultCount();

/// Returns the request ID of the oldest website-data result.
@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'webview_flutter_linux_website_data_result_request_id',
)
external int webviewFlutterLinuxWebsiteDataResultRequestId();

/// Returns the status of the oldest website-data result.
@ffi.Native<ffi.Int32 Function()>(
  symbol: 'webview_flutter_linux_website_data_result_status',
)
external int webviewFlutterLinuxWebsiteDataResultStatus();

/// Returns the UTF-8 error length of the oldest website-data result.
@ffi.Native<ffi.Size Function()>(
  symbol: 'webview_flutter_linux_website_data_result_error_length',
)
external int webviewFlutterLinuxWebsiteDataResultErrorLength();

/// Copies the oldest website-data result's UTF-8 error.
@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_website_data_result_copy_error',
)
external int webviewFlutterLinuxWebsiteDataResultCopyError(
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Removes the oldest website-data result after Dart copies it.
@ffi.Native<ffi.Int32 Function()>(
  symbol: 'webview_flutter_linux_website_data_result_pop',
)
external int webviewFlutterLinuxWebsiteDataResultPop();

/// Starts an application-wide cookie insertion for [requestId].
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Char>,
  )
>(symbol: 'webview_flutter_linux_cookie_set')
external int webviewFlutterLinuxCookieSet(
  int requestId,
  ffi.Pointer<ffi.Char> name,
  ffi.Pointer<ffi.Char> value,
  ffi.Pointer<ffi.Char> domain,
  ffi.Pointer<ffi.Char> path,
);

/// Starts an application-wide cookie lookup for [uri].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_cookie_get',
)
external int webviewFlutterLinuxCookieGet(
  int requestId,
  ffi.Pointer<ffi.Char> uri,
);

/// Starts an application-wide cookie clear for [requestId].
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_cookie_clear',
)
external int webviewFlutterLinuxCookieClear(int requestId);

/// Sets WPE's application-wide cookie accept policy.
@ffi.Native<ffi.Int32 Function(ffi.Int32)>(
  symbol: 'webview_flutter_linux_cookie_set_accept_policy',
)
external int webviewFlutterLinuxCookieSetAcceptPolicy(int policy);

/// Starts an asynchronous read of WPE's effective cookie accept policy.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_cookie_get_accept_policy',
)
external int webviewFlutterLinuxCookieGetAcceptPolicy(int requestId);

/// Enables or disables ITP for WPE's application-wide network session.
@ffi.Native<ffi.Int32 Function(ffi.Int32)>(
  symbol: 'webview_flutter_linux_cookie_set_itp_enabled',
)
external int webviewFlutterLinuxCookieSetItpEnabled(int enabled);

/// Returns whether ITP is enabled for WPE's application-wide network session.
@ffi.Native<ffi.Int32 Function()>(
  symbol: 'webview_flutter_linux_cookie_itp_enabled',
)
external int webviewFlutterLinuxCookieItpEnabled();

/// Returns the number of completed global cookie operations.
@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'webview_flutter_linux_cookie_result_count',
)
external int webviewFlutterLinuxCookieResultCount();

/// Returns the request ID of the oldest cookie result.
@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'webview_flutter_linux_cookie_result_request_id',
)
external int webviewFlutterLinuxCookieResultRequestId();

/// Returns the status of the oldest cookie result.
@ffi.Native<ffi.Int32 Function()>(
  symbol: 'webview_flutter_linux_cookie_result_status',
)
external int webviewFlutterLinuxCookieResultStatus();

/// Returns whether cookies existed before the oldest clear operation.
@ffi.Native<ffi.Int32 Function()>(
  symbol: 'webview_flutter_linux_cookie_result_had_cookies',
)
external int webviewFlutterLinuxCookieResultHadCookies();

/// Returns the accept policy carried by the oldest cookie result.
@ffi.Native<ffi.Int32 Function()>(
  symbol: 'webview_flutter_linux_cookie_result_accept_policy',
)
external int webviewFlutterLinuxCookieResultAcceptPolicy();

/// Returns the UTF-8 error length of the oldest cookie result.
@ffi.Native<ffi.Size Function()>(
  symbol: 'webview_flutter_linux_cookie_result_error_length',
)
external int webviewFlutterLinuxCookieResultErrorLength();

/// Copies the oldest cookie result's UTF-8 error.
@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_cookie_result_copy_error',
)
external int webviewFlutterLinuxCookieResultCopyError(
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Returns the cookie count carried by the oldest lookup result.
@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'webview_flutter_linux_cookie_result_cookie_count',
)
external int webviewFlutterLinuxCookieResultCookieCount();

/// Returns a cookie field's UTF-8 length.
///
/// Field 0 is name, 1 value, 2 domain, and 3 path.
@ffi.Native<ffi.Size Function(ffi.Uint32, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_cookie_result_field_length',
)
external int webviewFlutterLinuxCookieResultFieldLength(
  int cookieIndex,
  int field,
);

/// Copies a cookie field from the oldest lookup result.
@ffi.Native<
  ffi.Int32 Function(ffi.Uint32, ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Size)
>(symbol: 'webview_flutter_linux_cookie_result_copy_field')
external int webviewFlutterLinuxCookieResultCopyField(
  int cookieIndex,
  int field,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Removes the oldest cookie result after Dart copies it.
@ffi.Native<ffi.Int32 Function()>(
  symbol: 'webview_flutter_linux_cookie_result_pop',
)
external int webviewFlutterLinuxCookieResultPop();

/// Returns the number of completed JavaScript requests waiting for Dart.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_javascript_result_count',
)
external int webviewFlutterLinuxWpeJavaScriptResultCount(int handle);

/// Returns the request ID of the oldest completed JavaScript request.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_javascript_result_request_id',
)
external int webviewFlutterLinuxWpeJavaScriptResultRequestId(int handle);

/// Returns the status of the oldest completed JavaScript request.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_javascript_result_status',
)
external int webviewFlutterLinuxWpeJavaScriptResultStatus(int handle);

/// Returns the UTF-8 payload length of the oldest JavaScript result.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_javascript_result_payload_length',
)
external int webviewFlutterLinuxWpeJavaScriptResultPayloadLength(int handle);

/// Copies the oldest JavaScript result payload into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_javascript_result_copy_payload',
)
external int webviewFlutterLinuxWpeJavaScriptResultCopyPayload(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Removes the oldest completed JavaScript request from the native queue.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_javascript_result_pop',
)
external int webviewFlutterLinuxWpeJavaScriptResultPop(int handle);

/// Installs [channel] as a document-start JavaScript message channel.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_add_javascript_channel',
)
external int webviewFlutterLinuxWpeAddJavaScriptChannel(
  int handle,
  ffi.Pointer<ffi.Char> channel,
);

/// Removes the JavaScript message channel named [channel].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_remove_javascript_channel',
)
external int webviewFlutterLinuxWpeRemoveJavaScriptChannel(
  int handle,
  ffi.Pointer<ffi.Char> channel,
);

/// Installs [source] as a document-start script and runs it in the current page.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_add_user_script',
)
external int webviewFlutterLinuxWpeAddUserScript(
  int handle,
  ffi.Pointer<ffi.Char> source,
);

/// Updates page scrollbar visibility and overscroll behavior.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32, ffi.Int32, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_page_presentation',
)
external int webviewFlutterLinuxWpeSetPagePresentation(
  int handle,
  int verticalScrollBarEnabled,
  int horizontalScrollBarEnabled,
  int overscrollMode,
);

/// Returns the number of browser-originated JavaScript messages waiting.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_javascript_message_count',
)
external int webviewFlutterLinuxWpeJavaScriptMessageCount(int handle);

/// Returns the channel-name length of the oldest queued message.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_javascript_message_channel_length',
)
external int webviewFlutterLinuxWpeJavaScriptMessageChannelLength(int handle);

/// Returns the payload length of the oldest queued message.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_javascript_message_payload_length',
)
external int webviewFlutterLinuxWpeJavaScriptMessagePayloadLength(int handle);

/// Copies the channel name of the oldest queued message into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_javascript_message_copy_channel',
)
external int webviewFlutterLinuxWpeJavaScriptMessageCopyChannel(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Copies the payload of the oldest queued message into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_javascript_message_copy_payload',
)
external int webviewFlutterLinuxWpeJavaScriptMessageCopyPayload(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Removes the oldest queued JavaScript message after Dart copies it.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_javascript_message_pop',
)
external int webviewFlutterLinuxWpeJavaScriptMessagePop(int handle);

/// Returns the number of pending WebKit navigation policy requests.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_policy_request_count',
)
external int webviewFlutterLinuxWpeNavigationPolicyRequestCount(int handle);

/// Returns the ID of the oldest pending navigation policy request.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_policy_request_id',
)
external int webviewFlutterLinuxWpeNavigationPolicyRequestId(int handle);

/// Returns whether the oldest policy request targets the main frame.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_policy_request_is_main_frame',
)
external int webviewFlutterLinuxWpeNavigationPolicyRequestIsMainFrame(
  int handle,
);

/// Returns the URL byte length of the oldest policy request.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_policy_request_url_length',
)
external int webviewFlutterLinuxWpeNavigationPolicyRequestUrlLength(int handle);

/// Copies the URL of the oldest policy request into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_navigation_policy_request_copy_url',
)
external int webviewFlutterLinuxWpeNavigationPolicyRequestCopyUrl(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Moves the oldest policy request into the delivered-decision set.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_policy_request_take',
)
external int webviewFlutterLinuxWpeNavigationPolicyRequestTake(int handle);

/// Resolves a delivered policy request by ID.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_navigation_policy_resolve',
)
external int webviewFlutterLinuxWpeNavigationPolicyResolve(
  int handle,
  int requestId,
  int allow,
);

/// Returns the number of retained JavaScript dialogs waiting for Dart.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_script_dialog_request_count',
)
external int webviewFlutterLinuxWpeScriptDialogRequestCount(int handle);

/// Returns the ID of the oldest waiting JavaScript dialog.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_script_dialog_request_id',
)
external int webviewFlutterLinuxWpeScriptDialogRequestId(int handle);

/// Returns WebKit's kind for the oldest waiting JavaScript dialog.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_script_dialog_request_kind',
)
external int webviewFlutterLinuxWpeScriptDialogRequestKind(int handle);

/// Returns whether the oldest prompt has default text.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_script_dialog_request_has_default_text',
)
external int webviewFlutterLinuxWpeScriptDialogRequestHasDefaultText(
  int handle,
);

/// Returns a JavaScript-dialog field's UTF-8 byte length.
///
/// Field 0 is message, 1 source URL, and 2 prompt default text.
@ffi.Native<ffi.Size Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_script_dialog_request_field_length',
)
external int webviewFlutterLinuxWpeScriptDialogRequestFieldLength(
  int handle,
  int field,
);

/// Copies a JavaScript-dialog string field into [destination].
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Size)
>(symbol: 'webview_flutter_linux_wpe_script_dialog_request_copy_field')
external int webviewFlutterLinuxWpeScriptDialogRequestCopyField(
  int handle,
  int field,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Moves the oldest JavaScript dialog into the delivered-request set.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_script_dialog_request_take',
)
external int webviewFlutterLinuxWpeScriptDialogRequestTake(int handle);

/// Resolves a delivered JavaScript dialog.
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Int32, ffi.Pointer<ffi.Char>)
>(symbol: 'webview_flutter_linux_wpe_script_dialog_resolve')
external int webviewFlutterLinuxWpeScriptDialogResolve(
  int handle,
  int requestId,
  int confirmed,
  ffi.Pointer<ffi.Char> promptText,
);

/// Returns the number of retained HTML file-input requests waiting for Dart.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_file_chooser_request_count',
)
external int webviewFlutterLinuxWpeFileChooserRequestCount(int handle);

/// Returns the ID of the oldest waiting file-input request.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_file_chooser_request_id',
)
external int webviewFlutterLinuxWpeFileChooserRequestId(int handle);

/// Returns one when the oldest file-input request accepts multiple files.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_file_chooser_request_allows_multiple',
)
external int webviewFlutterLinuxWpeFileChooserRequestAllowsMultiple(int handle);

/// Returns the number of values in an accepted-type or selected-file list.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_file_chooser_request_value_count',
)
external int webviewFlutterLinuxWpeFileChooserRequestValueCount(
  int handle,
  int collection,
);

/// Returns one file-input value's UTF-8 byte length.
@ffi.Native<ffi.Size Function(ffi.Uint64, ffi.Uint32, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_file_chooser_request_value_length',
)
external int webviewFlutterLinuxWpeFileChooserRequestValueLength(
  int handle,
  int collection,
  int index,
);

/// Copies one accepted MIME type or previously selected path.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Pointer<ffi.Uint8>,
    ffi.Size,
  )
>(symbol: 'webview_flutter_linux_wpe_file_chooser_request_copy_value')
external int webviewFlutterLinuxWpeFileChooserRequestCopyValue(
  int handle,
  int collection,
  int index,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Moves the oldest file-input request into the delivered-request set.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_file_chooser_request_take',
)
external int webviewFlutterLinuxWpeFileChooserRequestTake(int handle);

/// Supplies filesystem paths for a delivered file-input request.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Uint64,
    ffi.Pointer<ffi.Pointer<ffi.Char>>,
    ffi.Size,
  )
>(symbol: 'webview_flutter_linux_wpe_file_chooser_request_select')
external int webviewFlutterLinuxWpeFileChooserRequestSelect(
  int handle,
  int requestId,
  ffi.Pointer<ffi.Pointer<ffi.Char>> files,
  int fileCount,
);

/// Cancels a delivered file-input request.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_file_chooser_request_cancel',
)
external int webviewFlutterLinuxWpeFileChooserRequestCancel(
  int handle,
  int requestId,
);

/// Returns the number of related WebViews ready for Flutter presentation.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_popup_request_count',
)
external int webviewFlutterLinuxWpePopupRequestCount(int handle);

/// Returns the native child handle of the oldest popup request.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_popup_request_child_handle',
)
external int webviewFlutterLinuxWpePopupRequestChildHandle(int handle);

/// Returns the UTF-8 requested-URL length of the oldest popup request.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_popup_request_url_length',
)
external int webviewFlutterLinuxWpePopupRequestUrlLength(int handle);

/// Copies the oldest popup request URL into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_popup_request_copy_url',
)
external int webviewFlutterLinuxWpePopupRequestCopyUrl(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Transfers the oldest popup child from its opener to Dart.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_popup_request_take',
)
external int webviewFlutterLinuxWpePopupRequestTake(int handle);

/// Atomically consumes a pending JavaScript `window.close` request.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_close_requested_take',
)
external int webviewFlutterLinuxWpeCloseRequestedTake(int handle);

/// Returns the number of queued HTML fullscreen transitions.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_fullscreen_event_count',
)
external int webviewFlutterLinuxWpeFullscreenEventCount(int handle);

/// Returns one for the oldest enter transition and zero for leave.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_fullscreen_event_value',
)
external int webviewFlutterLinuxWpeFullscreenEventValue(int handle);

/// Removes the oldest HTML fullscreen transition.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_fullscreen_event_pop',
)
external int webviewFlutterLinuxWpeFullscreenEventPop(int handle);

/// Refreshes WebKit's bounded native accessibility-tree snapshot.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_accessibility_refresh',
)
external int webviewFlutterLinuxWpeAccessibilityRefresh(
  int handle,
  int maximumNodes,
);

/// Returns the UTF-8 JSON length of the current accessibility snapshot.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_accessibility_json_length',
)
external int webviewFlutterLinuxWpeAccessibilityJsonLength(int handle);

/// Copies the current accessibility snapshot JSON into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_accessibility_copy_json',
)
external int webviewFlutterLinuxWpeAccessibilityCopyJson(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Invokes one advertised action on a generation-scoped accessibility node.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Uint32, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_accessibility_do_action',
)
external int webviewFlutterLinuxWpeAccessibilityDoAction(
  int handle,
  int generation,
  int nodeIndex,
  int actionIndex,
);

/// Moves browser focus to a generation-scoped accessibility node.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_accessibility_grab_focus',
)
external int webviewFlutterLinuxWpeAccessibilityGrabFocus(
  int handle,
  int generation,
  int nodeIndex,
);

/// Replaces editable text on a generation-scoped accessibility node.
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Uint32, ffi.Pointer<ffi.Char>)
>(symbol: 'webview_flutter_linux_wpe_accessibility_set_text')
external int webviewFlutterLinuxWpeAccessibilitySetText(
  int handle,
  int generation,
  int nodeIndex,
  ffi.Pointer<ffi.Char> text,
);

/// Updates text selection offsets on a generation-scoped accessibility node.
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Uint32, ffi.Int32, ffi.Int32)
>(symbol: 'webview_flutter_linux_wpe_accessibility_set_selection')
external int webviewFlutterLinuxWpeAccessibilitySetSelection(
  int handle,
  int generation,
  int nodeIndex,
  int startOffset,
  int endOffset,
);

/// Increments or decrements a generation-scoped native accessibility value.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Uint32, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_accessibility_adjust_value',
)
external int webviewFlutterLinuxWpeAccessibilityAdjustValue(
  int handle,
  int generation,
  int nodeIndex,
  int direction,
);

/// Returns the number of downloads paused for a Flutter destination.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_download_request_count',
)
external int webviewFlutterLinuxWpeDownloadRequestCount(int handle);

/// Returns the stable identifier of the oldest paused download.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_download_request_id',
)
external int webviewFlutterLinuxWpeDownloadRequestId(int handle);

/// Returns the response length for the oldest download, or -1 if unknown.
@ffi.Native<ffi.Int64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_download_request_content_length',
)
external int webviewFlutterLinuxWpeDownloadRequestContentLength(int handle);

/// Returns a URI, suggested-filename, or MIME field's UTF-8 byte length.
@ffi.Native<ffi.Size Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_download_request_field_length',
)
external int webviewFlutterLinuxWpeDownloadRequestFieldLength(
  int handle,
  int field,
);

/// Copies a URI, suggested-filename, or MIME field for the oldest download.
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Size)
>(symbol: 'webview_flutter_linux_wpe_download_request_copy_field')
external int webviewFlutterLinuxWpeDownloadRequestCopyField(
  int handle,
  int field,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Moves the oldest download into the delivered-request set.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_download_request_take',
)
external int webviewFlutterLinuxWpeDownloadRequestTake(int handle);

/// Sets a local destination, or cancels when [destination] is null.
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Pointer<ffi.Char>, ffi.Int32)
>(symbol: 'webview_flutter_linux_wpe_download_request_resolve')
external int webviewFlutterLinuxWpeDownloadRequestResolve(
  int handle,
  int requestId,
  ffi.Pointer<ffi.Char> destination,
  int allowOverwrite,
);

/// Returns the number of queued download lifecycle transitions.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_download_event_count',
)
external int webviewFlutterLinuxWpeDownloadEventCount(int handle);

/// Returns the download ID associated with the oldest transition.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_download_event_id',
)
external int webviewFlutterLinuxWpeDownloadEventId(int handle);

/// Returns the stable kind of the oldest download transition.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_download_event_kind',
)
external int webviewFlutterLinuxWpeDownloadEventKind(int handle);

/// Returns total bytes received for the oldest download transition.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_download_event_received_bytes',
)
external int webviewFlutterLinuxWpeDownloadEventReceivedBytes(int handle);

/// Returns expected total bytes, or -1 when unknown.
@ffi.Native<ffi.Int64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_download_event_content_length',
)
external int webviewFlutterLinuxWpeDownloadEventContentLength(int handle);

/// Returns WebKit's native error code for the oldest transition.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_download_event_error_code',
)
external int webviewFlutterLinuxWpeDownloadEventErrorCode(int handle);

/// Returns a destination or error-detail field's UTF-8 byte length.
@ffi.Native<ffi.Size Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_download_event_field_length',
)
external int webviewFlutterLinuxWpeDownloadEventFieldLength(
  int handle,
  int field,
);

/// Copies a destination or error-detail field from the oldest transition.
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Size)
>(symbol: 'webview_flutter_linux_wpe_download_event_copy_field')
external int webviewFlutterLinuxWpeDownloadEventCopyField(
  int handle,
  int field,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Removes the oldest download transition after its fields are copied.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_download_event_pop',
)
external int webviewFlutterLinuxWpeDownloadEventPop(int handle);

/// Returns the number of retained permission requests waiting for Dart.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_permission_request_count',
)
external int webviewFlutterLinuxWpePermissionRequestCount(int handle);

/// Returns the ID of the oldest waiting permission request.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_permission_request_id',
)
external int webviewFlutterLinuxWpePermissionRequestId(int handle);

/// Returns the resource bitmask of the oldest permission request.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_permission_request_resource_types',
)
external int webviewFlutterLinuxWpePermissionRequestResourceTypes(int handle);

/// Returns the source URL byte length of the oldest permission request.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_permission_request_url_length',
)
external int webviewFlutterLinuxWpePermissionRequestUrlLength(int handle);

/// Copies the source URL of the oldest permission request.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_permission_request_copy_url',
)
external int webviewFlutterLinuxWpePermissionRequestCopyUrl(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Moves the oldest permission request into the delivered-request set.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_permission_request_take',
)
external int webviewFlutterLinuxWpePermissionRequestTake(int handle);

/// Grants or denies one delivered permission request.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_permission_request_resolve',
)
external int webviewFlutterLinuxWpePermissionRequestResolve(
  int handle,
  int requestId,
  int allow,
);

/// Returns the number of page notifications waiting for Flutter presentation.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_notification_count',
)
external int webviewFlutterLinuxWpeNotificationCount(int handle);

/// Returns the bridge ID of the oldest waiting notification.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_notification_id',
)
external int webviewFlutterLinuxWpeNotificationId(int handle);

/// Returns whether the oldest waiting notification supplied a tag.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_notification_has_tag',
)
external int webviewFlutterLinuxWpeNotificationHasTag(int handle);

/// Returns a title, body, tag, or URL field's UTF-8 byte length.
@ffi.Native<ffi.Size Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_notification_field_length',
)
external int webviewFlutterLinuxWpeNotificationFieldLength(
  int handle,
  int field,
);

/// Copies a field from the oldest waiting notification.
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Size)
>(symbol: 'webview_flutter_linux_wpe_notification_copy_field')
external int webviewFlutterLinuxWpeNotificationCopyField(
  int handle,
  int field,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Moves the oldest notification into Flutter's active-notification set.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_notification_take',
)
external int webviewFlutterLinuxWpeNotificationTake(int handle);

/// Closes (`0`) or clicks (`1`) one active page notification.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_notification_respond',
)
external int webviewFlutterLinuxWpeNotificationRespond(
  int handle,
  int notificationId,
  int action,
);

/// Returns the number of active notifications withdrawn by WebKit.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_notification_closed_count',
)
external int webviewFlutterLinuxWpeNotificationClosedCount(int handle);

/// Removes and returns the oldest withdrawn notification ID.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_notification_closed_take',
)
external int webviewFlutterLinuxWpeNotificationClosedTake(int handle);

/// Returns the number of retained HTTP-authentication requests waiting for Dart.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_http_auth_request_count',
)
external int webviewFlutterLinuxWpeHttpAuthRequestCount(int handle);

/// Returns the ID of the oldest HTTP-authentication request.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_http_auth_request_id',
)
external int webviewFlutterLinuxWpeHttpAuthRequestId(int handle);

/// Returns whether the oldest HTTP-authentication request includes a realm.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_http_auth_request_has_realm',
)
external int webviewFlutterLinuxWpeHttpAuthRequestHasRealm(int handle);

/// Returns the UTF-8 byte length of a host or realm field.
@ffi.Native<ffi.Size Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_http_auth_request_field_length',
)
external int webviewFlutterLinuxWpeHttpAuthRequestFieldLength(
  int handle,
  int field,
);

/// Copies a host or realm field into [destination].
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Size)
>(symbol: 'webview_flutter_linux_wpe_http_auth_request_copy_field')
external int webviewFlutterLinuxWpeHttpAuthRequestCopyField(
  int handle,
  int field,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Moves the oldest HTTP-authentication request into the delivered set.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_http_auth_request_take',
)
external int webviewFlutterLinuxWpeHttpAuthRequestTake(int handle);

/// Supplies username/password credentials for a delivered request.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Uint64,
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Char>,
  )
>(symbol: 'webview_flutter_linux_wpe_http_auth_request_proceed')
external int webviewFlutterLinuxWpeHttpAuthRequestProceed(
  int handle,
  int requestId,
  ffi.Pointer<ffi.Char> username,
  ffi.Pointer<ffi.Char> password,
);

/// Cancels a delivered HTTP-authentication request.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_http_auth_request_cancel',
)
external int webviewFlutterLinuxWpeHttpAuthRequestCancel(
  int handle,
  int requestId,
);

/// Returns the number of retained TLS certificate failures waiting for Dart.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_ssl_auth_error_count',
)
external int webviewFlutterLinuxWpeSslAuthErrorCount(int handle);

/// Returns the ID of the oldest TLS certificate failure.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_ssl_auth_error_id',
)
external int webviewFlutterLinuxWpeSslAuthErrorId(int handle);

/// Returns GLib's TLS certificate-error bitmask for the oldest failure.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_ssl_auth_error_flags',
)
external int webviewFlutterLinuxWpeSslAuthErrorFlags(int handle);

/// Returns the UTF-8 byte length of the oldest TLS failure URL.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_ssl_auth_error_url_length',
)
external int webviewFlutterLinuxWpeSslAuthErrorUrlLength(int handle);

/// Copies the oldest TLS failure URL into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_ssl_auth_error_copy_url',
)
external int webviewFlutterLinuxWpeSslAuthErrorCopyUrl(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Returns the DER certificate byte length for the oldest TLS failure.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_ssl_auth_error_certificate_length',
)
external int webviewFlutterLinuxWpeSslAuthErrorCertificateLength(int handle);

/// Copies the DER certificate for the oldest TLS failure.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_ssl_auth_error_copy_certificate',
)
external int webviewFlutterLinuxWpeSslAuthErrorCopyCertificate(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Moves the oldest TLS failure into the delivered set.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_ssl_auth_error_take',
)
external int webviewFlutterLinuxWpeSslAuthErrorTake(int handle);

/// Cancels or proceeds past a delivered TLS certificate failure.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_ssl_auth_error_resolve',
)
external int webviewFlutterLinuxWpeSslAuthErrorResolve(
  int handle,
  int requestId,
  int proceed,
);

/// Returns the number of native navigation events waiting for Dart.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_event_count',
)
external int webviewFlutterLinuxWpeNavigationEventCount(int handle);

/// Returns the wire kind of the oldest queued navigation event.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_event_kind',
)
external int webviewFlutterLinuxWpeNavigationEventKind(int handle);

/// Returns the progress percentage carried by the oldest navigation event.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_event_progress',
)
external int webviewFlutterLinuxWpeNavigationEventProgress(int handle);

/// Returns the native error or HTTP status code of the oldest event.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_event_code',
)
external int webviewFlutterLinuxWpeNavigationEventCode(int handle);

/// Returns one for a main-frame event, zero otherwise, and negative if unknown.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_event_is_main_frame',
)
external int webviewFlutterLinuxWpeNavigationEventIsMainFrame(int handle);

/// Returns the UTF-8 detail length of the oldest navigation event.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_event_detail_length',
)
external int webviewFlutterLinuxWpeNavigationEventDetailLength(int handle);

/// Copies the detail string of the oldest event into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_navigation_event_copy_detail',
)
external int webviewFlutterLinuxWpeNavigationEventCopyDetail(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Returns the UTF-8 URL length of the oldest queued navigation event.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_event_url_length',
)
external int webviewFlutterLinuxWpeNavigationEventUrlLength(int handle);

/// Copies the oldest queued navigation event URL into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_navigation_event_copy_url',
)
external int webviewFlutterLinuxWpeNavigationEventCopyUrl(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Removes the oldest queued navigation event.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_navigation_event_pop',
)
external int webviewFlutterLinuxWpeNavigationEventPop(int handle);

/// Intentionally terminates [handle]'s web process for recovery testing.
///
/// Production applications must not call this diagnostic entry point.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_terminate_web_process_for_testing',
)
external int webviewFlutterLinuxWpeTerminateWebProcessForTesting(int handle);

/// Resizes the browser to logical [width] by [height] at [scale].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32, ffi.Uint32, ffi.Double)>(
  symbol: 'webview_flutter_linux_wpe_resize',
)
external int webviewFlutterLinuxWpeResize(
  int handle,
  int width,
  int height,
  double scale,
);

/// Updates whether [handle] receives keyboard focus.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_focus',
)
external int webviewFlutterLinuxWpeSetFocus(int handle, int focused);

/// Returns the latest browser editable-state generation.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_generation',
)
external int webviewFlutterLinuxWpeInputMethodGeneration(int handle);

/// Returns whether a browser editable element currently owns input focus.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_focused',
)
external int webviewFlutterLinuxWpeInputMethodFocused(int handle);

/// Returns the UTF-8 byte length of the browser's surrounding text.
@ffi.Native<ffi.Size Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_text_length',
)
external int webviewFlutterLinuxWpeInputMethodTextLength(int handle);

/// Copies the browser's surrounding text into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_input_method_copy_text',
)
external int webviewFlutterLinuxWpeInputMethodCopyText(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Returns WebKit's UTF-8 byte offset for the editable cursor.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_cursor_index',
)
external int webviewFlutterLinuxWpeInputMethodCursorIndex(int handle);

/// Returns WebKit's UTF-8 byte offset for the opposite selection endpoint.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_selection_index',
)
external int webviewFlutterLinuxWpeInputMethodSelectionIndex(int handle);

/// Returns the latest browser caret rectangle components.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_cursor_x',
)
external int webviewFlutterLinuxWpeInputMethodCursorX(int handle);

@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_cursor_y',
)
external int webviewFlutterLinuxWpeInputMethodCursorY(int handle);

@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_cursor_width',
)
external int webviewFlutterLinuxWpeInputMethodCursorWidth(int handle);

@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_cursor_height',
)
external int webviewFlutterLinuxWpeInputMethodCursorHeight(int handle);

/// Returns WebKit's input-purpose enum value for the active editor.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_purpose',
)
external int webviewFlutterLinuxWpeInputMethodPurpose(int handle);

/// Returns WebKit's input-hints bitmask for the active editor.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_hints',
)
external int webviewFlutterLinuxWpeInputMethodHints(int handle);

/// Replaces the active browser preedit string and cursor.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_input_method_set_preedit',
)
external int webviewFlutterLinuxWpeInputMethodSetPreedit(
  int handle,
  ffi.Pointer<ffi.Char> text,
  int cursorOffset,
);

/// Commits a completed input-method string into the active browser editor.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_input_method_commit',
)
external int webviewFlutterLinuxWpeInputMethodCommit(
  int handle,
  ffi.Pointer<ffi.Char> text,
);

/// Cancels the active browser composition.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_input_method_cancel_preedit',
)
external int webviewFlutterLinuxWpeInputMethodCancelPreedit(int handle);

/// Deletes Unicode characters relative to the browser editor cursor.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_input_method_delete_surrounding',
)
external int webviewFlutterLinuxWpeInputMethodDeleteSurrounding(
  int handle,
  int offset,
  int characterCount,
);

/// Updates whether [handle] is visible to the application.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_visibility',
)
external int webviewFlutterLinuxWpeSetVisibility(int handle, int visible);

/// Updates whether JavaScript execution is enabled for [handle].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_javascript_enabled',
)
external int webviewFlutterLinuxWpeSetJavaScriptEnabled(
  int handle,
  int enabled,
);

/// Updates whether media playback requires a user gesture for [handle].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_media_playback_requires_user_gesture',
)
external int webviewFlutterLinuxWpeSetMediaPlaybackRequiresUserGesture(
  int handle,
  int required,
);

/// Updates whether media may play inline instead of requiring fullscreen.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_media_playback_allows_inline',
)
external int webviewFlutterLinuxWpeSetMediaPlaybackAllowsInline(
  int handle,
  int allowed,
);

/// Updates whether WebRTC and its MediaStream dependency are enabled.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_webrtc_enabled',
)
external int webviewFlutterLinuxWpeSetWebRtcEnabled(int handle, int enabled);

/// Enables deterministic camera and microphone devices for browser tests.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_mock_capture_devices_enabled',
)
external int webviewFlutterLinuxWpeSetMockCaptureDevicesEnabled(
  int handle,
  int enabled,
);

/// Returns whether deterministic browser capture devices are enabled.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_mock_capture_devices_enabled',
)
external int webviewFlutterLinuxWpeMockCaptureDevicesEnabled(int handle);

/// Updates whether Encrypted Media Extensions are enabled for [handle].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_encrypted_media_enabled',
)
external int webviewFlutterLinuxWpeSetEncryptedMediaEnabled(
  int handle,
  int enabled,
);

/// Updates whether WebKit developer extras are enabled for [handle].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_inspectable',
)
external int webviewFlutterLinuxWpeSetInspectable(int handle, int inspectable);

/// Enables or disables Geolocation API permission requests for [handle].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_geolocation_enabled',
)
external int webviewFlutterLinuxWpeSetGeolocationEnabled(
  int handle,
  int enabled,
);

/// Returns the native per-view geolocation gate, or a negative status.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_geolocation_enabled',
)
external int webviewFlutterLinuxWpeGeolocationEnabled(int handle);

/// Controls whether JavaScript can open a related window without a gesture.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol:
      'webview_flutter_linux_wpe_set_javascript_can_open_windows_automatically',
)
external int webviewFlutterLinuxWpeSetJavaScriptCanOpenWindowsAutomatically(
  int handle,
  int enabled,
);

/// Returns the effective automatic JavaScript-window preference.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_javascript_can_open_windows_automatically',
)
external int webviewFlutterLinuxWpeJavaScriptCanOpenWindowsAutomatically(
  int handle,
);

/// Controls whether page scripts may run clipboard editing commands.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_javascript_can_access_clipboard',
)
external int webviewFlutterLinuxWpeSetJavaScriptCanAccessClipboard(
  int handle,
  int enabled,
);

/// Returns the effective JavaScript clipboard-command policy.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_javascript_can_access_clipboard',
)
external int webviewFlutterLinuxWpeJavaScriptCanAccessClipboard(int handle);

/// Updates whether documents loaded from `file:` may request local resources.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_file_access_enabled',
)
external int webviewFlutterLinuxWpeSetFileAccessEnabled(
  int handle,
  int enabled,
);

/// Updates whether a local-file document may access resources from any origin.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_universal_file_access_enabled',
)
external int webviewFlutterLinuxWpeSetUniversalFileAccessEnabled(
  int handle,
  int enabled,
);

/// Returns effective WPE capability bits, or a negative status on failure.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_capability_flags',
)
external int webviewFlutterLinuxWpeCapabilityFlags(int handle);

/// Replaces the user agent, or restores WebKit's default when [userAgent] is
/// null.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_set_user_agent',
)
external int webviewFlutterLinuxWpeSetUserAgent(
  int handle,
  ffi.Pointer<ffi.Char> userAgent,
);

/// Returns the UTF-8 byte length of the current user agent.
@ffi.Native<ffi.IntPtr Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_user_agent_length',
)
external int webviewFlutterLinuxWpeUserAgentLength(int handle);

/// Copies the current user agent into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_copy_user_agent',
)
external int webviewFlutterLinuxWpeCopyUserAgent(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Returns the UTF-8 length of WebKit's current URI, or negative if absent.
@ffi.Native<ffi.IntPtr Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_uri_length',
)
external int webviewFlutterLinuxWpeUriLength(int handle);

/// Copies WebKit's current URI into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_copy_uri',
)
external int webviewFlutterLinuxWpeCopyUri(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Returns the UTF-8 length of WebKit's current title, or negative if absent.
@ffi.Native<ffi.IntPtr Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_title_length',
)
external int webviewFlutterLinuxWpeTitleLength(int handle);

/// Copies WebKit's current title into [destination].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_copy_title',
)
external int webviewFlutterLinuxWpeCopyTitle(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Sets the native page zoom factor.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Double)>(
  symbol: 'webview_flutter_linux_wpe_set_zoom_level',
)
external int webviewFlutterLinuxWpeSetZoomLevel(int handle, double zoomLevel);

/// Sets text-only zoom as a percentage, or restores page zoom at 100.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Int32)>(
  symbol: 'webview_flutter_linux_wpe_set_text_zoom',
)
external int webviewFlutterLinuxWpeSetTextZoom(int handle, int textZoom);

/// Returns effective text-only zoom as a percentage, or zero on failure.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_text_zoom',
)
external int webviewFlutterLinuxWpeTextZoom(int handle);

/// Returns the native page zoom factor.
@ffi.Native<ffi.Double Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_zoom_level',
)
external double webviewFlutterLinuxWpeZoomLevel(int handle);

/// Sets the view background using a packed ARGB color.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_set_background_color',
)
external int webviewFlutterLinuxWpeSetBackgroundColor(int handle, int argb);

/// Sends a mouse move, leave, or enter event in physical surface coordinates.
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Int32, ffi.Int32, ffi.Uint32, ffi.Int32)
>(symbol: 'webview_flutter_linux_wpe_send_mouse_move')
external int webviewFlutterLinuxWpeSendMouseMove(
  int handle,
  int x,
  int y,
  int modifiers,
  int pointerTransition,
);

/// Sends a mouse-button transition in physical surface coordinates.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Int32,
    ffi.Int32,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Int32,
    ffi.Int32,
  )
>(symbol: 'webview_flutter_linux_wpe_send_mouse_button')
external int webviewFlutterLinuxWpeSendMouseButton(
  int handle,
  int x,
  int y,
  int modifiers,
  int button,
  int mouseUp,
  int clickCount,
);

/// Sends a mouse-wheel event in physical surface coordinates.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Int32,
    ffi.Int32,
    ffi.Uint32,
    ffi.Int32,
    ffi.Int32,
  )
>(symbol: 'webview_flutter_linux_wpe_send_mouse_wheel')
external int webviewFlutterLinuxWpeSendMouseWheel(
  int handle,
  int x,
  int y,
  int modifiers,
  int deltaX,
  int deltaY,
);

/// Sends one precise touchpad-scroll update or its terminating stop event.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Int32,
    ffi.Int32,
    ffi.Uint32,
    ffi.Double,
    ffi.Double,
    ffi.Int32,
  )
>(symbol: 'webview_flutter_linux_wpe_send_trackpad_scroll')
external int webviewFlutterLinuxWpeSendTrackpadScroll(
  int handle,
  int x,
  int y,
  int modifiers,
  double deltaX,
  double deltaY,
  int isStop,
);

/// Sends one touchscreen contact event in physical surface coordinates.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Int32,
    ffi.Int32,
  )
>(symbol: 'webview_flutter_linux_wpe_send_touch')
external int webviewFlutterLinuxWpeSendTouch(
  int handle,
  int eventType,
  int modifiers,
  int sequenceId,
  int x,
  int y,
);

/// Sends a Chromium-compatible key event to the native browser view.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Int32,
    ffi.Int32,
    ffi.Uint32,
    ffi.Uint32,
  )
>(symbol: 'webview_flutter_linux_wpe_send_key')
external int webviewFlutterLinuxWpeSendKey(
  int handle,
  int eventType,
  int modifiers,
  int windowsKeyCode,
  int nativeKeyCode,
  int character,
  int unmodifiedCharacter,
);

/// Returns the native clipboard revision, or a negative value on failure.
@ffi.Native<ffi.Int64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_change_count',
)
external int webviewFlutterLinuxWpeClipboardChangeCount(int handle);

/// Returns the byte length of the native clipboard's UTF-8 text.
@ffi.Native<ffi.IntPtr Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_text_length',
)
external int webviewFlutterLinuxWpeClipboardTextLength(int handle);

/// Copies native clipboard bytes into [destination].
///
/// [destinationLength] must be at least the value returned by
/// [webviewFlutterLinuxWpeClipboardTextLength]. The result is the number of
/// bytes copied, or a negative status code.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_copy_text',
)
external int webviewFlutterLinuxWpeClipboardCopyText(
  int handle,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Replaces the native clipboard text with null-terminated UTF-8 [text].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_wpe_clipboard_set_text',
)
external int webviewFlutterLinuxWpeClipboardSetText(
  int handle,
  ffi.Pointer<ffi.Char> text,
);

/// Starts exporting every transferable WPE clipboard format to the desktop.
///
/// Returns a non-zero request identifier, or zero when no request was queued.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_system_clipboard_export',
)
external int webviewFlutterLinuxSystemClipboardExport(int handle);

/// Starts reading the desktop clipboard on the native clipboard worker.
@ffi.Native<ffi.Uint64 Function()>(
  symbol: 'webview_flutter_linux_system_clipboard_import',
)
external int webviewFlutterLinuxSystemClipboardImport();

/// Returns zero while [requestId] is pending, one on success, or a failure.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_system_clipboard_request_status',
)
external int webviewFlutterLinuxSystemClipboardRequestStatus(int requestId);

/// Consumes a completed desktop read and applies it to [handle]'s WPE view.
///
/// [plainTextOverride] may be null. Otherwise native code uses it for the
/// plain-text representation while retaining imported rich formats.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint64, ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_system_clipboard_apply_import',
)
external int webviewFlutterLinuxSystemClipboardApplyImport(
  int handle,
  int requestId,
  ffi.Pointer<ffi.Char> plainTextOverride,
);

/// Releases a completed or abandoned system clipboard request.
@ffi.Native<ffi.Void Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_system_clipboard_discard',
)
external void webviewFlutterLinuxSystemClipboardDiscard(int requestId);

/// Returns a counter that changes when WPE exposes a new context menu.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_generation',
)
external int webviewFlutterLinuxWpeContextMenuGeneration(int handle);

/// Returns the context menu's horizontal physical coordinate.
@ffi.Native<ffi.Double Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_x',
)
external double webviewFlutterLinuxWpeContextMenuX(int handle);

/// Returns the context menu's vertical physical coordinate.
@ffi.Native<ffi.Double Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_y',
)
external double webviewFlutterLinuxWpeContextMenuY(int handle);

/// Returns the number of entries in the current native context menu.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_count',
)
external int webviewFlutterLinuxWpeContextMenuItemCount(int handle);

/// Returns the UTF-8 byte length of the context-menu item at [index].
@ffi.Native<ffi.Size Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_title_length',
)
external int webviewFlutterLinuxWpeContextMenuItemTitleLength(
  int handle,
  int index,
);

/// Copies the context-menu item title at [index] into [destination].
@ffi.Native<
  ffi.Int32 Function(ffi.Uint64, ffi.Uint32, ffi.Pointer<ffi.Uint8>, ffi.Size)
>(symbol: 'webview_flutter_linux_wpe_context_menu_item_copy_title')
external int webviewFlutterLinuxWpeContextMenuItemCopyTitle(
  int handle,
  int index,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Returns a nonzero value when the context-menu item is a separator.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_is_separator',
)
external int webviewFlutterLinuxWpeContextMenuItemIsSeparator(
  int handle,
  int index,
);

/// Returns a nonzero value when the context-menu item can be activated.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_is_enabled',
)
external int webviewFlutterLinuxWpeContextMenuItemIsEnabled(
  int handle,
  int index,
);

/// Returns WebKit's stable stock-action identifier for a context-menu item.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_item_stock_action',
)
external int webviewFlutterLinuxWpeContextMenuItemStockAction(
  int handle,
  int index,
);

/// Activates the native context-menu item at [index].
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_activate',
)
external int webviewFlutterLinuxWpeContextMenuActivate(int handle, int index);

/// Dismisses the current native context menu without activating an item.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_context_menu_dismiss',
)
external int webviewFlutterLinuxWpeContextMenuDismiss(int handle);

/// Returns a counter changed whenever an HTML option menu opens or closes.
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_generation',
)
external int webviewFlutterLinuxWpeOptionMenuGeneration(int handle);

/// Returns one while an HTML option menu is retained for Flutter.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_available',
)
external int webviewFlutterLinuxWpeOptionMenuAvailable(int handle);

/// Returns the option element's horizontal physical coordinate.
@ffi.Native<ffi.Double Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_x',
)
external double webviewFlutterLinuxWpeOptionMenuX(int handle);

/// Returns the option element's vertical physical coordinate.
@ffi.Native<ffi.Double Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_y',
)
external double webviewFlutterLinuxWpeOptionMenuY(int handle);

/// Returns the option element's physical width.
@ffi.Native<ffi.Double Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_width',
)
external double webviewFlutterLinuxWpeOptionMenuWidth(int handle);

/// Returns the option element's physical height.
@ffi.Native<ffi.Double Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_height',
)
external double webviewFlutterLinuxWpeOptionMenuHeight(int handle);

/// Returns the number of entries in the current HTML option menu.
@ffi.Native<ffi.Uint32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_item_count',
)
external int webviewFlutterLinuxWpeOptionMenuItemCount(int handle);

/// Returns the UTF-8 length of an option label or tooltip.
@ffi.Native<ffi.Size Function(ffi.Uint64, ffi.Uint32, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_item_field_length',
)
external int webviewFlutterLinuxWpeOptionMenuItemFieldLength(
  int handle,
  int index,
  int field,
);

/// Copies an option label or tooltip into [destination].
@ffi.Native<
  ffi.Int32 Function(
    ffi.Uint64,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Pointer<ffi.Uint8>,
    ffi.Size,
  )
>(symbol: 'webview_flutter_linux_wpe_option_menu_item_copy_field')
external int webviewFlutterLinuxWpeOptionMenuItemCopyField(
  int handle,
  int index,
  int field,
  ffi.Pointer<ffi.Uint8> destination,
  int destinationLength,
);

/// Returns one when an option entry is a non-selectable group label.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_item_is_group_label',
)
external int webviewFlutterLinuxWpeOptionMenuItemIsGroupLabel(
  int handle,
  int index,
);

/// Returns one when an option entry belongs to an option group.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_item_is_group_child',
)
external int webviewFlutterLinuxWpeOptionMenuItemIsGroupChild(
  int handle,
  int index,
);

/// Returns one when an option entry may be activated.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_item_is_enabled',
)
external int webviewFlutterLinuxWpeOptionMenuItemIsEnabled(
  int handle,
  int index,
);

/// Returns one when an option entry is currently selected.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_item_is_selected',
)
external int webviewFlutterLinuxWpeOptionMenuItemIsSelected(
  int handle,
  int index,
);

/// Activates one option and closes its native menu.
@ffi.Native<ffi.Int32 Function(ffi.Uint64, ffi.Uint32)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_activate',
)
external int webviewFlutterLinuxWpeOptionMenuActivate(int handle, int index);

/// Closes the current HTML option menu without changing its value.
@ffi.Native<ffi.Int32 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_option_menu_dismiss',
)
external int webviewFlutterLinuxWpeOptionMenuDismiss(int handle);

/// Claims or releases WPE's application-global geolocation provider.
@ffi.Native<ffi.Int32 Function(ffi.Int32)>(
  symbol: 'webview_flutter_linux_geolocation_set_provider_enabled',
)
external int webviewFlutterLinuxGeolocationSetProviderEnabled(int enabled);

/// Returns the number of queued geolocation-provider lifecycle events.
@ffi.Native<ffi.Uint32 Function()>(
  symbol: 'webview_flutter_linux_geolocation_event_count',
)
external int webviewFlutterLinuxGeolocationEventCount();

/// Returns whether the oldest event starts or stops position updates.
@ffi.Native<ffi.Int32 Function()>(
  symbol: 'webview_flutter_linux_geolocation_event_active',
)
external int webviewFlutterLinuxGeolocationEventActive();

/// Returns whether the oldest event requests high-accuracy updates.
@ffi.Native<ffi.Int32 Function()>(
  symbol: 'webview_flutter_linux_geolocation_event_high_accuracy',
)
external int webviewFlutterLinuxGeolocationEventHighAccuracy();

/// Removes the oldest geolocation-provider lifecycle event.
@ffi.Native<ffi.Int32 Function()>(
  symbol: 'webview_flutter_linux_geolocation_event_pop',
)
external int webviewFlutterLinuxGeolocationEventPop();

/// Publishes a validated position to WPE's application-global manager.
@ffi.Native<
  ffi.Int32 Function(
    ffi.Double,
    ffi.Double,
    ffi.Double,
    ffi.Uint64,
    ffi.Uint32,
    ffi.Double,
    ffi.Double,
    ffi.Double,
    ffi.Double,
  )
>(symbol: 'webview_flutter_linux_geolocation_update_position')
external int webviewFlutterLinuxGeolocationUpdatePosition(
  double latitude,
  double longitude,
  double accuracy,
  int timestampSeconds,
  int optionalMask,
  double altitude,
  double altitudeAccuracy,
  double heading,
  double speed,
);

/// Reports that the registered application provider cannot obtain a position.
@ffi.Native<ffi.Int32 Function(ffi.Pointer<ffi.Char>)>(
  symbol: 'webview_flutter_linux_geolocation_failed',
)
external int webviewFlutterLinuxGeolocationFailed(
  ffi.Pointer<ffi.Char> message,
);

/// Returns the number of frames WPE has painted for [handle].
@ffi.Native<ffi.Uint64 Function(ffi.Uint64)>(
  symbol: 'webview_flutter_linux_wpe_paint_count',
)
external int webviewFlutterLinuxWpePaintCount(int handle);
