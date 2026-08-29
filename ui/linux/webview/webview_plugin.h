#ifndef LUMEN_WEBVIEW_WEBVIEW_PLUGIN_H_
#define LUMEN_WEBVIEW_WEBVIEW_PLUGIN_H_

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#include <flutter_linux/flutter_linux.h>

// Registers the LumenWebView plugin. Called from main.cc after
// fl_register_plugins().
void lumen_webview_plugin_register_with_registrar(FlPluginRegistrar* registrar);

#endif  // LUMEN_WEBVIEW_WEBVIEW_PLUGIN_H_