#ifndef LUMEN_WEBVIEW_NATIVE_WEB_VIEW_H_
#define LUMEN_WEBVIEW_NATIVE_WEB_VIEW_H_

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#include <flutter_linux/flutter_linux.h>

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

// A single WebKitGTK webview rendered into an engine texture.
//
// The webview lives inside a hidden toplevel window so it can be realized and
// draw offscreen; a [LumenPixelBufferTexture] exposes the resulting RGBA
// pixels to Flutter as an external texture. Frames are produced on the GTK
// main thread (a periodic tick while loading / dirty) and the render thread
// only copies the last finished frame out of a cached buffer.
class NativeWebView {
 public:
  NativeWebView(FlBinaryMessenger* messenger,
                FlTextureRegistrar* texture_registrar,
                WebKitUserContentFilterStore* filter_store,
                const std::string& id, const std::string& url);
  ~NativeWebView();

  FlMethodChannel* channel() const { return channel_; }
  int64_t texture_id() const { return texture_id_; }

  // Create + register the engine texture. Returns the texture id (or -1).
  int64_t CreateTexture();

  void SetSize(double width, double height);
  void LoadUrl(const std::string& url);
  void GoBack();
  void GoForward();
  void Reload();
  void Stop();
  void Evaluate(const std::string& js);

  void SetContentFilters(const std::vector<std::string>& parts);
  void ClearContentFilters();

  // Called by the engine's pixel-buffer texture (render thread).
  bool CopyPixels(const uint8_t** buffer, uint32_t* width, uint32_t* height);

  // Full teardown. Only touchable from the GTK main thread.
  void Dispose();

  // Emits a notification method on the per-view channel. Takes ownership of
  // [args] (or NULL). GTK main thread.
  void SendMethod(const gchar* name, FlValue* args = nullptr);
  // WebKit load-state transition → Dart 'onLoadState'/'onLoadFailed'.
  void OnLoadChanged(WebKitLoadEvent event);
  void OnLoadFailed(const gchar* failing_uri);

  // (called from texture copy_pixels / filter-save callbacks)
  void RequestFrame();
  void AddInstalledFilter(WebKitUserContentFilter* filter);
  WebKitWebView* GetWebView() const;

  // Called by the GTK timeout.
  gboolean Tick();

 private:
  void ScheduleFrame();
  void RenderFrame();

  FlMethodChannel* channel_ = nullptr;
  FlTextureRegistrar* texture_registrar_ = nullptr;
  WebKitUserContentFilterStore* filter_store_ = nullptr;
  GtkWidget* window_ = nullptr;  // hidden toplevel container
  GtkWidget* web_view_ = nullptr;
  GObject* texture_ = nullptr;   // LumenPixelBufferTexture
  std::string id_;
  int64_t texture_id_ = -1;

  double width_ = 0;
  double height_ = 0;

  std::mutex render_mutex_;
  std::vector<uint8_t> buffer_;
  uint32_t buffer_width_ = 0;
  uint32_t buffer_height_ = 0;
  std::atomic_bool dirty_{false};

  guint tick_source_ = 0;
  bool loading_ = false;
  bool disposed_ = false;

  // Filters currently installed on the webview's user content manager.
  std::vector<WebKitUserContentFilter*> installed_filters_;
};

#endif  // LUMEN_WEBVIEW_NATIVE_WEB_VIEW_H_