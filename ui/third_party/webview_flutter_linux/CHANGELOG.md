## 0.1.0-dev.2

- Add an opt-in JavaScript clipboard policy backed by WPE's native setting,
  including trusted page copy through the desktop clipboard bridge.
- Share one application-scoped WPE display across independent and related
  WebViews so clipboard and input identity survive `window.open` lifecycles.
- Preserve DOM state, history, scroll position, detached JavaScript work, and
  input when the same controller is unmounted and later presented again.
- Preserve DOM state, scroll position, hidden JavaScript work, and input when
  an attached WebView is backgrounded and later resumed.
- Add explicit, idempotent `LinuxWebViewController.dispose()` support so apps
  can deterministically release controller-owned native WebViews after
  unmounting their surfaces.
- Keep context-menu Cut, Copy, and Paste reliable after popup/view lifecycle
  changes by reconciling Flutter text with rich native clipboard formats and
  routing focused-editor actions through the input bridge.
- Navigate WebKit's native back-forward list from dedicated desktop mouse back
  and forward buttons.
- Match the platform-independent single-window behavior for `target="_blank"`
  and `window.open(url)` when no Linux popup callback is registered, while
  retaining independently renderable related WebViews for opted-in callers.
- Normalize public JavaScript string and null results to the non-WKWebView
  contract used by the official `webview_flutter` integration suite.

- Honor federated WebView gesture recognizers and layout direction while
  preserving mouse-wheel and touchpad pan/zoom input on the texture surface.
- Release and replace controller-owned renderers safely when a keyed WebView
  widget is rebuilt with a different controller.
- Claim mouse-wheel signals for the deepest WebView so a surrounding Flutter
  scrollable does not respond to the same event.
- Resolve Flutter context and option menus only against the renderer that
  opened them, including during controller replacement.
- Require a user gesture for media autoplay by default, matching Android
  WebView and WKWebView while retaining an explicit Linux autoplay opt-out.
- Observe native URI changes outside the page-load lifecycle so fragment and
  History API updates reach `onUrlChange`, and suppress racing internal blank
  page events before the first requested navigation.
- Replace first-paint navigation completion with native WebKit lifecycle and
  estimated-progress events.
- Track page-driven main-frame URLs and redirects in the Dart controller's
  current URL and history state.
- Add an ABI-version guard and a bounded, per-WebView native event queue.
- Correct mouse-wheel direction and forward two-axis touchpad pans plus native
  touchscreen contacts, including fractional movement, gesture termination,
  and pointer-leave delivery.
- Preserve single, double, and triple mouse-click counts for browser selection
  and activation behavior.
- Reflect WebKit's named CSS cursors on the Flutter texture surface and accept
  valid custom cursor buffers when supplied by WPE.
- Add asynchronous JavaScript execution with request-scoped results and native
  error propagation.
- Implement page-title lookup and programmatic scroll position APIs.
- Support enabling and disabling JavaScript before or after view attachment.
- Support custom user agents before initial navigation and at runtime.
- Add document-start JavaScript channels with ordered browser-to-Dart message
  delivery and runtime removal.
- Forward WebKit main-resource failures and HTTP 4xx/5xx responses through the
  federated navigation delegate.
- Forward failed images, scripts, stylesheets, frames, and other subordinate
  resources with `isForMainFrame` set to false.
- Retain WebKit policy decisions across FFI so asynchronous Dart navigation
  delegates can allow or prevent page-initiated loads.
- Fix initial navigation racing engine-handle discovery during attachment.
- Add native background-color control and optional touchpad pinch zoom through
  WebKit's page zoom level.
- Add Android-compatible text-only zoom percentages, retained across attachment
  and related popup creation, with 100 percent restoring ordinary page zoom.
- Forward JavaScript console output and throttled main-frame scroll changes
  through a document-start event bridge, preserving serializable structure
  while omitting only cyclic object references.
- Implement asynchronous HTTP/Application/Cache API cache clearing and local
  storage clearing through WebKit's website-data manager.
- Implement application-wide cookie set, lookup, and clearing through WPE's
  application-scoped default session, including persistent storage for
  non-session cookies across starts.
- Add application-wide cookie acceptance and Intelligent Tracking Prevention
  controls, including an Android-compatible third-party-cookie convenience API.
- Forward alert, confirm, prompt, and before-unload JavaScript dialogs through
  the federated controller callbacks with asynchronous native resolution.
- Retain WPE permission requests across FFI and expose camera, microphone,
  display-capture, geolocation, notification, device-info, protected-media,
  website-data-access, and XR decisions through the federated permission API;
  answer origin-scoped Permissions API queries from those host decisions.
- Route page-created Web Notifications through application-owned Flutter UI,
  including copied title, body, tag, and source URL metadata plus explicit
  click, close, page-withdrawal, navigation, web-process termination, and
  disposal lifecycles.
- Add an Android-compatible, default-enabled per-WebView geolocation switch
  that overrides and cancels pending application permission grants when off.
- Match Android's automatic JavaScript-window default with a retained per-view
  WPE setting and related-window inheritance.
- Move AT-SPI tree reads and semantic actions to a dedicated native worker,
  using direct, bounded GIO D-Bus calls instead of crash-prone libatspi proxies,
  plus failure backoff, immutable generation snapshots, deterministic disposal
  ordering, and one-generation action retention.
- Implement independent horizontal and vertical scrollbar visibility plus
  overscroll disabling with a user-level WebKit stylesheet applied to all
  frames.
- Forward WPE HTTP authentication challenges through the federated navigation
  delegate with retained asynchronous requests and exactly-once credential or
  cancellation handling.
- Forward TLS certificate failures with DER certificate data through the
  federated SSL-auth callback, including explicit cancellation and guarded
  host/certificate exceptions followed by reload.
- Do not emit `onPageFinished` after a cancelled TLS or other failed
  main-resource load; explicit TLS proceed still reloads and completes.
- Support custom HTTP headers on GET `loadRequest` navigations, including
  requests queued before widget attachment and controller-managed history or
  reload operations.
- Report abnormal WPE web-process exits as federated
  `webContentProcessTerminated` resource errors, reject stranded asynchronous
  operations, and allow application-controlled reload recovery.
- Use WebKit's native back-forward list and reload operation after attachment
  so history traversal preserves browser state and original request semantics.
- Load HTML through WebKit's native document API with base-URI semantics, and
  read the current URI and title directly from WebKit without JavaScript.
- Load Flutter assets from the packaged Linux asset directory so relative CSS,
  images, scripts, and other local resources resolve from asset documents.
- Clear cache and local storage through WebKit's application-wide data manager,
  including before a WebView widget attaches.
- Route HTML file inputs to an asynchronous Flutter-owned file selector with
  accepted MIME types, initial selections, multiple-file mode, and explicit
  selection or cancellation without invoking WebKit's GTK chooser.
- Render HTML select controls as Flutter option menus, preserving option groups,
  disabled and selected states, tooltips, element-relative positioning, and
  explicit native activation or dismissal.
- Bridge Flutter's system text input to a Rust-only WebKit input-method context
  with composed preedit, committed Unicode text, surrounding-text deletion,
  browser selection synchronization, and caret-positioned candidate UI.
- Add Flutter-owned download destinations with native WPE progress, failure,
  completion, overwrite protection, and safe cancellation when unhandled.
- Expose `target="_blank"` and `window.open()` as independently renderable,
  related WebViews with explicit Flutter ownership and `window.close()` events.
- Present WebKit fullscreen content through a root Flutter overlay while
  preserving the originating WebView, input state, and page-driven exit events.
- Mirror WebKit's native AT-SPI tree into Flutter semantics with labels, roles,
  state, bounds, focus, actions, text editing, selection, and value adjustment.
- Load POST requests with arbitrary binary bodies through WebKit's native
  form-history state while preserving browser networking, navigation, and
  caller-supplied main-resource headers.
- Accept a GET request body without throwing when WPE ignores it, matching
  Android WebView's `loadRequest` behavior.
- Add Linux controller controls for media-playback gesture policy and WebKit
  developer inspectability, including pre-attachment configuration.
- Add WPE-native controls for inline media playback, WebRTC, encrypted media,
  and local or universal file-origin access, with separate reporting for host
  features that were compiled out of the installed browser runtime.
- Add opt-in deterministic camera and microphone devices so applications and
  headless tests can exercise the real WebKit permission path without capture
  hardware; permission grants remain under Flutter control.
- Replace the plain-text-only bridge with GTK-free, asynchronous Wayland/X11
  clipboard synchronization for HTML, images, URI lists, RTF, text aliases,
  and bounded custom MIME formats while retaining a plain-text fallback.
- Add an opt-in Linux back/forward navigation gesture that distinguishes
  horizontal touchpad swipes from vertical page scrolling and preserves pans
  toward unavailable history directions.
- Notify Linux clients when backward-history availability changes, including
  controller requests made before attachment and native WPE navigations.
- Avoid re-entering Flutter's process-wide GLib main context from Dart FFI,
  preventing hot restart from aborting while WPE events are pending.
- Track Rust source files as native-asset build inputs and allow package
  development to opt into the local source build.
- Add an application-global geolocation provider bridge with GeoClue fallback,
  lifecycle and high-accuracy notifications, and validated position or error
  updates.
- Preserve logical CSS viewport and input, menu, and IME coordinates while
  scaling WPE render buffers for HiDPI displays.
- Retain each native WPE view in its controller across temporary widget
  detachments, preserving document state, history, media, and pending work with
  single-surface attachment leases and platform-thread native finalization.
- Create native WPE views on demand from controller APIs before first widget
  attachment, with deduplicated engine discovery and a weak completion pump.

## 0.1.0-dev.1

- Add an experimental WPE WebKit implementation of the current
  `webview_flutter` platform interface for Linux.
- Render accelerated WPE DMA-BUF frames through an Irondash Flutter texture.
- Support basic navigation, input, audio, plain-text clipboard bridging, and
  context menus.
- Support multiple simultaneous WebViews through handle-scoped native state.
