import 'web_controller.dart';

/// Registry of all live embedded webviews, keyed by tab id.
///
/// A [LumenWebViewController] registers itself when its platform view is
/// created and unregisters on dispose. The ad-blocker and tab navigation
/// delegate to the controller for whichever tab is active.
class WebControllers {
  WebControllers._();

  static final WebControllers instance = WebControllers._();

  final Map<String, LumenWebViewController> _controllers = {};

  LumenWebViewController? operator [](String tabId) => _controllers[tabId];

  bool get isEmpty => _controllers.isEmpty;

  Iterable<LumenWebViewController> get all => _controllers.values;

  void register(LumenWebViewController controller) {
    _controllers[controller.id] = controller;
  }

  void unregister(LumenWebViewController controller) {
    _controllers.remove(controller.id);
  }
}