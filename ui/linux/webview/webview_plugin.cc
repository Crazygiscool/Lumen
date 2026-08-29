#include "webview_plugin.h"

#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "native_web_view.h"

// The plugin is a plain C++ object owned by the registrar (via
// g_object_set_data_full). It does not need to be a GObject itself: Flutter
// only requires the bind to fl_register_plugins() + this function.

struct WebviewPlugin {
  FlPluginRegistrar* registrar = nullptr;
  FlBinaryMessenger* messenger = nullptr;
  FlTextureRegistrar* texture_registrar = nullptr;
  WebKitUserContentFilterStore* filter_store = nullptr;
  FlMethodChannel* probe_channel = nullptr;
  std::map<std::string, NativeWebView*> webviews;
};

// Per-view channel binding: resolves the NativeWebView and gives access to the
// plugin (for map bookkeeping on dispose).
struct ViewBinding {
  WebviewPlugin* plugin;
  NativeWebView* view;
  std::string id;
};

namespace {

void RespondSuccess(FlMethodCall* call, FlValue* result) {
  g_autoptr(FlMethodSuccessResponse) response =
      result != nullptr ? fl_method_success_response_new(result)
                        : fl_method_success_response_new(nullptr);
  fl_method_call_respond(call, FL_METHOD_RESPONSE(response), nullptr);
}

void RespondError(FlMethodCall* call, const gchar* code, const gchar* message) {
  g_autoptr(FlMethodErrorResponse) response =
      fl_method_error_response_new(code, message, nullptr);
  fl_method_call_respond(call, FL_METHOD_RESPONSE(response), nullptr);
}

void RespondNotImplemented(FlMethodCall* call) {
  g_autoptr(FlMethodNotImplementedResponse) response =
      fl_method_not_implemented_response_new();
  fl_method_call_respond(call, FL_METHOD_RESPONSE(response), nullptr);
}

// ---------------------------------------------------------------------------
// Per-view method dispatch.
// ---------------------------------------------------------------------------

void DispatchViewCall(ViewBinding* binding, FlMethodCall* call) {
  NativeWebView* view = binding->view;
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (strcmp(method, "createTexture") == 0) {
    int64_t id = view->CreateTexture();
    if (id < 0) {
      RespondError(call, "create_error", "could not register webview texture");
    } else {
      RespondSuccess(call, fl_value_new_int(id));
    }
    return;
  }
  if (strcmp(method, "setSize") == 0) {
    double width = 0;
    double height = 0;
    if (args != nullptr) {
      FlValue* fw = fl_value_lookup_string(args, "w");
      FlValue* fh = fl_value_lookup_string(args, "h");
      if (fw != nullptr) width = fl_value_get_float(fw);
      if (fh != nullptr) height = fl_value_get_float(fh);
    }
    view->SetSize(width, height);
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "loadUrl") == 0) {
    if (args != nullptr) {
      FlValue* url = fl_value_lookup_string(args, "url");
      if (url != nullptr) view->LoadUrl(fl_value_get_string(url));
    }
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "goBack") == 0) {
    view->GoBack();
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "goForward") == 0) {
    view->GoForward();
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "reload") == 0) {
    view->Reload();
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "stop") == 0) {
    view->Stop();
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "evaluateJavascript") == 0) {
    if (args != nullptr) {
      FlValue* js = fl_value_lookup_string(args, "js");
      if (js != nullptr) view->Evaluate(fl_value_get_string(js));
    }
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "setContentFilters") == 0) {
    std::vector<std::string> parts;
    if (args != nullptr) {
      FlValue* list = fl_value_lookup_string(args, "parts");
      if (list != nullptr) {
        size_t length = fl_value_get_length(list);
        for (size_t i = 0; i < length; i++) {
          FlValue* item = fl_value_get_list_value(list, i);
          if (fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
            parts.push_back(fl_value_get_string(item));
          }
        }
      }
    }
    view->SetContentFilters(parts);
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "clearContentFilters") == 0) {
    view->ClearContentFilters();
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "dispose") == 0) {
    RespondSuccess(call, nullptr);
    // Destroy synchronously after responding; nothing below touches [view].
    binding->plugin->webviews.erase(binding->id);
    delete view;
    delete binding;
    return;
  }
  RespondNotImplemented(call);
}

void OnViewMethodCall(FlMethodChannel* channel, FlMethodCall* call,
                      gpointer user_data) {
  (void)channel;
  ViewBinding* binding = reinterpret_cast<ViewBinding*>(user_data);
  DispatchViewCall(binding, call);
}

// ---------------------------------------------------------------------------
// Probe channel: 'ping' + 'createView'.
// ---------------------------------------------------------------------------

void OnProbeMethodCall(FlMethodChannel* channel, FlMethodCall* call,
                       gpointer user_data) {
  (void)channel;
  WebviewPlugin* plugin = reinterpret_cast<WebviewPlugin*>(user_data);
  const gchar* method = fl_method_call_get_name(call);

  if (strcmp(method, "ping") == 0) {
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "createView") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    std::string id;
    std::string url;
    if (args != nullptr) {
      FlValue* fid = fl_value_lookup_string(args, "id");
      FlValue* furl = fl_value_lookup_string(args, "url");
      if (fid != nullptr) id = fl_value_get_string(fid);
      if (furl != nullptr) url = fl_value_get_string(furl);
    }
    if (id.empty()) {
      RespondError(call, "bad_args", "createView requires an id");
      return;
    }

    auto found = plugin->webviews.find(id);
    if (found != plugin->webviews.end()) {
      RespondSuccess(call, fl_value_new_int(found->second->texture_id()));
      return;
    }

    NativeWebView* view = new NativeWebView(plugin->messenger,
                                            plugin->texture_registrar,
                                            plugin->filter_store, id, url);
    int64_t texture_id = view->CreateTexture();
    if (texture_id < 0) {
      delete view;
      RespondError(call, "create_error", "could not register webview texture");
      return;
    }

    plugin->webviews[id] = view;
    ViewBinding* binding = new ViewBinding{plugin, view, id};
    fl_method_channel_set_method_call_handler(view->channel(),
                                              OnViewMethodCall, binding,
                                              nullptr);
    RespondSuccess(call, fl_value_new_int(texture_id));
    return;
  }
  RespondNotImplemented(call);
}

// ---------------------------------------------------------------------------
// Plugin lifecycle.
// ---------------------------------------------------------------------------

void WebviewPluginDestroy(gpointer data) {
  WebviewPlugin* plugin = reinterpret_cast<WebviewPlugin*>(data);
  for (auto& entry : plugin->webviews) {
    delete entry.second;
  }
  plugin->webviews.clear();
  if (plugin->probe_channel != nullptr) {
    g_clear_object(&plugin->probe_channel);
  }
  if (plugin->filter_store != nullptr) {
    g_object_unref(plugin->filter_store);
  }
  delete plugin;
}

}  // namespace

void lumen_webview_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  WebviewPlugin* plugin = new WebviewPlugin();
  plugin->registrar = registrar;
  plugin->messenger = fl_plugin_registrar_get_messenger(registrar);
  plugin->texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);
  plugin->filter_store =
      webkit_user_content_filter_store_new("lumen-content-filters");

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->probe_channel = fl_method_channel_new(
      plugin->messenger, "lumen.webview/probe", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(plugin->probe_channel,
                                            OnProbeMethodCall, plugin, nullptr);

  g_object_set_data_full(G_OBJECT(registrar), "lumen-webview-plugin", plugin,
                         WebviewPluginDestroy);
}