#include "native_web_view.h"

#include <cairo/cairo.h>
#include <cstring>

#include <jsc/jsc.h>

// ---------------------------------------------------------------------------
// LumenPixelBufferTexture — FlPixelBufferTexture subclass that serves the last
// rendered frame out of the owner's cached RGBA buffer.
// ---------------------------------------------------------------------------

struct LumenPixelBufferTexture {
  FlPixelBufferTexture parent_instance;
  NativeWebView* owner;
};

struct LumenPixelBufferTextureClass {
  FlPixelBufferTextureClass parent_class;
};

G_DEFINE_TYPE(LumenPixelBufferTexture, lumen_pixel_buffer_texture,
              fl_pixel_buffer_texture_get_type())

#define LUMEN_PIXEL_BUFFER_TEXTURE(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), lumen_pixel_buffer_texture_get_type(), \
                              LumenPixelBufferTexture))
#define LUMEN_PIXEL_BUFFER_TEXTURE_CLASS(klass) \
  (G_TYPE_CHECK_CLASS_CAST((klass), lumen_pixel_buffer_texture_get_type(), \
                           LumenPixelBufferTextureClass))

namespace {

LumenPixelBufferTexture* ToLumen(FlPixelBufferTexture* texture) {
  return reinterpret_cast<LumenPixelBufferTexture*>(texture);
}

gboolean on_copy_pixels(FlPixelBufferTexture* texture,
                        const uint8_t** out_buffer, uint32_t* width,
                        uint32_t* height, GError** error) {
  LumenPixelBufferTexture* self = ToLumen(texture);
  if (self->owner == nullptr) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED, "webview disposed");
    return FALSE;
  }
  return self->owner->CopyPixels(out_buffer, width, height) ? TRUE : FALSE;
}

}  // namespace

static void lumen_pixel_buffer_texture_init(LumenPixelBufferTexture* self) {
  self->owner = nullptr;
}

static void lumen_pixel_buffer_texture_class_init(
    LumenPixelBufferTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = on_copy_pixels;
}

static FlPixelBufferTexture* lumen_pixel_buffer_texture_new(NativeWebView* owner) {
  LumenPixelBufferTexture* self = reinterpret_cast<LumenPixelBufferTexture*>(
      g_object_new(lumen_pixel_buffer_texture_get_type(), nullptr));
  self->owner = owner;
  return FL_PIXEL_BUFFER_TEXTURE(self);
}

// ---------------------------------------------------------------------------
// Filter-save guard: WebKit content-filter saves complete asynchronously.
// [NativeWebView] can be destroyed while a save is in flight, so each save
// carries a small struct that the webview marks dead on dispose. Every save
// callback runs on the GTK main thread, so no locking is needed.
// ---------------------------------------------------------------------------

struct FilterSavePending {
  NativeWebView* view;
  gboolean alive;
  GBytes* source;  // kept alive until the async save completes
};

namespace {

void on_store_save_finished(GObject* source, GAsyncResult* res, gpointer data) {
  FilterSavePending* pending = reinterpret_cast<FilterSavePending*>(data);
  if (pending == nullptr) return;
  NativeWebView* self = pending->view;
  gboolean alive = pending->alive;
  if (pending->source != nullptr) {
    g_bytes_unref(pending->source);
  }
  delete pending;
  if (!alive || self == nullptr) return;

  GError* error = nullptr;
  WebKitUserContentFilter* filter =
      webkit_user_content_filter_store_save_finish(
          WEBKIT_USER_CONTENT_FILTER_STORE(source), res, &error);
  if (filter == nullptr) {
    if (error != nullptr) g_error_free(error);
    return;
  }
  WebKitUserContentManager* manager = webkit_web_view_get_user_content_manager(
      self->GetWebView());
  if (manager == nullptr) {
    g_object_unref(filter);
    return;
  }
  webkit_user_content_manager_add_filter(manager, filter);
  self->AddInstalledFilter(filter);
  self->RequestFrame();
}

void on_load_changed(WebKitWebView* view, WebKitLoadEvent event,
                     gpointer user_data) {
  NativeWebView* self = reinterpret_cast<NativeWebView*>(user_data);
  self->OnLoadChanged(event);
  self->RequestFrame();
}

void on_uri_notify(GObject* object, GParamSpec*, gpointer user_data) {
  NativeWebView* self = reinterpret_cast<NativeWebView*>(user_data);
  const gchar* uri = webkit_web_view_get_uri(self->GetWebView());
  if (uri != nullptr) {
    self->SendMethod("onUrlChanged", fl_value_new_string(uri));
  }
  self->RequestFrame();
}

void on_title_notify(GObject* object, GParamSpec*, gpointer user_data) {
  NativeWebView* self = reinterpret_cast<NativeWebView*>(user_data);
  const gchar* title = webkit_web_view_get_title(self->GetWebView());
  if (title != nullptr) {
    self->SendMethod("onTitleChanged", fl_value_new_string(title));
  }
}

void on_progress_notify(GObject* object, GParamSpec*, gpointer user_data) {
  NativeWebView* self = reinterpret_cast<NativeWebView*>(user_data);
  double progress = webkit_web_view_get_estimated_load_progress(self->GetWebView());
  self->SendMethod("onProgress", fl_value_new_float(static_cast<float>(progress)));
}

void on_navigation_notify(GObject* object, GParamSpec*, gpointer user_data) {
  NativeWebView* self = reinterpret_cast<NativeWebView*>(user_data);
  WebKitWebView* view = self->GetWebView();
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_take(map, fl_value_new_string("back"),
                    fl_value_new_bool(webkit_web_view_can_go_back(view)));
  fl_value_set_take(map, fl_value_new_string("forward"),
                    fl_value_new_bool(webkit_web_view_can_go_forward(view)));
  self->SendMethod("onNavigation", map);
}

// Main-frame load failure. Cancelled loads (stop/reload) are ignored.
gboolean on_load_failed(WebKitWebView* view, WebKitLoadEvent event,
                        const gchar* failing_uri, GError* error,
                        gpointer user_data) {
  (void)view;
  if (event == WEBKIT_LOAD_STARTED &&
      g_error_matches(error, WEBKIT_NETWORK_ERROR,
                      WEBKIT_NETWORK_ERROR_CANCELLED)) {
    return FALSE;
  }
  NativeWebView* self = reinterpret_cast<NativeWebView*>(user_data);
  self->OnLoadFailed(failing_uri);
  return FALSE;
}

// Keep all navigation inside the current tab: new windows inline into this
// view and every other navigation proceeds normally.
void on_decide_policy(WebKitWebView*, WebKitPolicyDecision* decision,
                      WebKitPolicyDecisionType, gpointer) {
  webkit_policy_decision_use(decision);
}

// target=_blank / window.open() reuse the current webview.
WebKitWebView* on_create(WebKitWebView* view, WebKitNavigationAction*, gpointer) {
  return view;
}

gboolean on_tick(gpointer data) {
  NativeWebView* self = reinterpret_cast<NativeWebView*>(data);
  return self->Tick();
}

}  // namespace

// ---------------------------------------------------------------------------
// NativeWebView
// ---------------------------------------------------------------------------

NativeWebView::NativeWebView(FlBinaryMessenger* messenger,
                             FlTextureRegistrar* texture_registrar,
                             WebKitUserContentFilterStore* filter_store,
                             const std::string& id, const std::string& url)
    : texture_registrar_(texture_registrar), filter_store_(filter_store), id_(id) {
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_default_size(GTK_WINDOW(window_), 1280, 720);
  gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);

  web_view_ = webkit_web_view_new();
  gtk_widget_set_hexpand(web_view_, TRUE);
  gtk_widget_set_vexpand(web_view_, TRUE);
  gtk_container_add(GTK_CONTAINER(window_), web_view_);
  gtk_widget_show(web_view_);
  gtk_widget_realize(window_);

  g_signal_connect(web_view_, "load-changed", G_CALLBACK(on_load_changed), this);
  g_signal_connect(web_view_, "load-failed", G_CALLBACK(on_load_failed), this);
  g_signal_connect(web_view_, "notify::uri", G_CALLBACK(on_uri_notify), this);
  g_signal_connect(web_view_, "notify::title", G_CALLBACK(on_title_notify), this);
  g_signal_connect(web_view_, "notify::estimated-load-progress",
                   G_CALLBACK(on_progress_notify), this);
  g_signal_connect(web_view_, "notify::can-go-back", G_CALLBACK(on_navigation_notify), this);
  g_signal_connect(web_view_, "notify::can-go-forward", G_CALLBACK(on_navigation_notify), this);
  g_signal_connect(web_view_, "decide-policy", G_CALLBACK(on_decide_policy), nullptr);
  g_signal_connect(web_view_, "create", G_CALLBACK(on_create), nullptr);

  if (!url.empty()) {
    webkit_web_view_load_uri(WEBKIT_WEB_VIEW(web_view_), url.c_str());
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  const std::string channel_name = "lumen.webview/" + id_;
  channel_ = fl_method_channel_new(messenger, channel_name.c_str(),
                                   FL_METHOD_CODEC(codec));
}

NativeWebView::~NativeWebView() {
  if (tick_source_ != 0) {
    g_source_remove(tick_source_);
    tick_source_ = 0;
  }
  if (texture_ != nullptr) {
    fl_texture_registrar_unregister_texture(texture_registrar_, FL_TEXTURE(texture_));
    g_object_unref(texture_);
    texture_ = nullptr;
  }
  ClearContentFilters();
  for (auto* filter : installed_filters_) {
    if (filter != nullptr) g_object_unref(filter);
  }
  installed_filters_.clear();
  if (channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
    g_clear_object(&channel_);
  }
  if (window_ != nullptr) {
    gtk_widget_destroy(window_);
    window_ = nullptr;
  }
}

void NativeWebView::Dispose() {
  if (disposed_) return;
  disposed_ = true;
}

void NativeWebView::SendMethod(const gchar* name, FlValue* args) {
  if (channel_ == nullptr) return;
  g_autoptr(FlValue) ref = args;
  fl_method_channel_invoke_method(channel_, name, ref, nullptr, nullptr, nullptr);
}

void NativeWebView::OnLoadChanged(WebKitLoadEvent event) {
  switch (event) {
    case WEBKIT_LOAD_STARTED:
      loading_ = true;
      SendMethod("onLoadState", fl_value_new_string("started"));
      break;
    case WEBKIT_LOAD_COMMITTED:
      SendMethod("onLoadState", fl_value_new_string("committed"));
      break;
    case WEBKIT_LOAD_REDIRECTED:
      break;
    case WEBKIT_LOAD_FINISHED:
      loading_ = false;
      SendMethod("onLoadState", fl_value_new_string("finished"));
      break;
  }
}

void NativeWebView::OnLoadFailed(const gchar* failing_uri) {
  loading_ = false;
  SendMethod("onLoadState", fl_value_new_string("failed"));
  if (failing_uri != nullptr) {
    SendMethod("onLoadFailed", fl_value_new_string(failing_uri));
  }
  RequestFrame();
}

int64_t NativeWebView::CreateTexture() {
  if (texture_ != nullptr) return texture_id_;
  texture_ = G_OBJECT(lumen_pixel_buffer_texture_new(this));
  if (!fl_texture_registrar_register_texture(texture_registrar_,
                                             FL_TEXTURE(texture_))) {
    g_object_unref(texture_);
    texture_ = nullptr;
    return -1;
  }
  texture_id_ = fl_texture_get_id(FL_TEXTURE(texture_));
  ScheduleFrame();
  return texture_id_;
}

void NativeWebView::SetSize(double width, double height) {
  if (width <= 0 || height <= 0) return;
  width_ = width;
  height_ = height;
  gint w = static_cast<gint>(width_);
  gint h = static_cast<gint>(height_);
  gtk_widget_set_size_request(window_, w, h);
  gtk_widget_set_size_request(web_view_, w, h);
  gtk_window_resize(GTK_WINDOW(window_), w, h);
  gtk_widget_queue_allocate(window_);
  gtk_widget_queue_resize(web_view_);
  ScheduleFrame();
}

void NativeWebView::LoadUrl(const std::string& url) {
  if (url.empty()) return;
  webkit_web_view_load_uri(WEBKIT_WEB_VIEW(web_view_), url.c_str());
}

void NativeWebView::GoBack() {
  webkit_web_view_go_back(WEBKIT_WEB_VIEW(web_view_));
}

void NativeWebView::GoForward() {
  webkit_web_view_go_forward(WEBKIT_WEB_VIEW(web_view_));
}

void NativeWebView::Reload() {
  webkit_web_view_reload(WEBKIT_WEB_VIEW(web_view_));
}

void NativeWebView::Stop() {
  webkit_web_view_stop_loading(WEBKIT_WEB_VIEW(web_view_));
}

void NativeWebView::Evaluate(const std::string& js) {
  webkit_web_view_evaluate_javascript(
      WEBKIT_WEB_VIEW(web_view_), js.c_str(), -1, nullptr, nullptr, nullptr,
      [](GObject* source, GAsyncResult* result, gpointer) {
        GError* error = nullptr;
        JSCValue* js_value = webkit_web_view_evaluate_javascript_finish(
            WEBKIT_WEB_VIEW(source), result, &error);
        if (js_value != nullptr) {
          g_object_unref(js_value);
        }
        if (error != nullptr) g_error_free(error);
      },
      nullptr);
}

void NativeWebView::SetContentFilters(const std::vector<std::string>& parts) {
  ClearContentFilters();

  // Monotonic epoch so repeated updates produce fresh, unique identifiers.
  static guint64 epoch = 0;
  ++epoch;

  for (size_t i = 0; i < parts.size(); i++) {
    std::string identifier =
        "lumen-" + std::to_string(epoch) + "-" + std::to_string(i);
    FilterSavePending* pending = new FilterSavePending{
        this, TRUE,
        g_bytes_new(parts[i].data(), static_cast<gssize>(parts[i].size()))};
    gchar* id_c = g_strdup(identifier.c_str());
    webkit_user_content_filter_store_save(
        filter_store_, id_c, pending->source, nullptr, on_store_save_finished,
        pending);
    g_free(id_c);
  }
  ScheduleFrame();
}

void NativeWebView::ClearContentFilters() {
  WebKitUserContentManager* manager =
      webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(web_view_));
  if (manager == nullptr) return;
  for (auto* filter : installed_filters_) {
    if (filter != nullptr) {
      webkit_user_content_manager_remove_filter(manager, filter);
      g_object_unref(filter);
    }
  }
  installed_filters_.clear();
}

bool NativeWebView::CopyPixels(const uint8_t** buffer, uint32_t* width,
                               uint32_t* height) {
  std::lock_guard<std::mutex> lock(render_mutex_);
  if (buffer_.empty()) return FALSE;
  *buffer = buffer_.data();
  *width = buffer_width_;
  *height = buffer_height_;
  return TRUE;
}

void NativeWebView::ScheduleFrame() {
  dirty_.store(true);
  if (tick_source_ == 0) {
    tick_source_ = g_timeout_add(33, on_tick, this);
  }
}

gboolean NativeWebView::Tick() {
  if (dirty_.load() || loading_) {
    RenderFrame();
    return G_SOURCE_CONTINUE;
  }
  tick_source_ = 0;
  return G_SOURCE_REMOVE;
}

void NativeWebView::RenderFrame() {
  if (disposed_) return;
  dirty_.store(false);
  const guint width = static_cast<guint>(width_);
  const guint height = static_cast<guint>(height_);
  if (width == 0 || height == 0 || web_view_ == nullptr || texture_ == nullptr) {
    return;
  }

  std::vector<uint8_t> frame(static_cast<size_t>(width) * height * 4);
  cairo_surface_t* surface = cairo_image_surface_create_for_data(
      frame.data(), CAIRO_FORMAT_ARGB32, static_cast<int>(width),
      static_cast<int>(height), static_cast<int>(width) * 4);
  cairo_t* cr = cairo_create(surface);
  // Clear to white first; WebKit does not repaint untouched areas.
  cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 1.0);
  cairo_paint(cr);
  gtk_widget_draw(web_view_, cr);
  cairo_destroy(cr);
  cairo_surface_destroy(surface);

  // Cairo ARGB32 stores B,G,R,A in little-endian memory → flip to RGBA.
  for (size_t i = 0; i < frame.size(); i += 4) {
    std::swap(frame[i], frame[i + 2]);
  }

  {
    std::lock_guard<std::mutex> lock(render_mutex_);
    buffer_.swap(frame);
    buffer_width_ = width;
    buffer_height_ = height;
  }
  fl_texture_registrar_mark_texture_frame_available(texture_registrar_,
                                                    FL_TEXTURE(texture_));
}

void NativeWebView::AddInstalledFilter(WebKitUserContentFilter* filter) {
  installed_filters_.push_back(filter);
}

void NativeWebView::RequestFrame() {
  ScheduleFrame();
}

WebKitWebView* NativeWebView::GetWebView() const {
  return WEBKIT_WEB_VIEW(web_view_);
}