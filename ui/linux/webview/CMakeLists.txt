# LumenWebView native plugin: WebKitGTK webviews rendered as Flutter textures.

set(WEBVIEW_SOURCES
  "webview_plugin.cc"
  "native_web_view.cc"
)

add_library(lumen_webview STATIC ${WEBVIEW_SOURCES})
apply_standard_settings(lumen_webview)

# flutter target provides the engine's flutter_linux/ headers.
target_link_libraries(lumen_webview PUBLIC flutter)

target_include_directories(lumen_webview PRIVATE
  "${PROJECT_BINARY_DIR}"
)

target_link_libraries(lumen_webview PUBLIC
  PkgConfig::GTK
  PkgConfig::WEBKIT
)