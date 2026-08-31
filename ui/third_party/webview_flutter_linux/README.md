# webview_flutter_linux

An experimental, non-endorsed Linux implementation of Flutter's official
[`webview_flutter`](https://pub.dev/packages/webview_flutter) plugin. It uses
the WPE WebKit runtime installed on the host and renders web content into a
Flutter texture without embedding a GTK browser widget or bundling a browser
engine.

Add the official plugin and this Linux implementation to a Flutter app:

```yaml
dependencies:
  webview_flutter: ^4.14.1
  webview_flutter_linux: ^0.1.0-dev.2
```

## Usage

Use the standard `webview_flutter` API:

```dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

final controller = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..loadRequest(Uri.parse('https://flutter.dev'));

class BrowserView extends StatelessWidget {
  const BrowserView({super.key});

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: controller);
  }
}
```

See [`example/lib/main.dart`](example/lib/main.dart) for a complete example.

## Linux runtime requirements

The native asset contains the Rust bridge, but it does not bundle a browser
engine. The target system must provide WPE WebKit 2.52 or newer, built with WPE
Platform support. Install the distribution package that provides
`libWPEWebKit-2.0.so.1`; its dependency resolver should also install the WPE
backend and the libraries used directly by the bridge:

- libepoxy (`libepoxy.so.0`)
- libsoup 3 (`libsoup-3.0.so.0`)
- GLib, GObject, and GIO
- ATK accessibility support (`libatk-1.0.so.0`)

For example:

```sh
# Arch Linux
sudo pacman -S wpewebkit

# Debian testing/unstable, when the repository provides WPE WebKit 2.52+
sudo apt install libwpewebkit-2.0-1

# Fedora, from a repository that provides WPE WebKit 2.52+
sudo dnf install wpewebkit
```

Older distribution releases may only provide an incompatible WPE WebKit
version. Confirm that both `wpe-webkit-2.0` and `wpe-platform-2.0` report 2.52
or newer when their pkg-config files are installed:

```sh
pkg-config --modversion wpe-webkit-2.0 wpe-platform-2.0
```

Git and path dependencies compile the Rust bridge locally and additionally
require the development packages for WPE WebKit, libepoxy, and ATK, plus
`pkg-config`. Published package releases use the prebuilt bridge and require
only the runtime libraries.

Audio and video format support comes from the host's GStreamer plugins. Install
the appropriate base, good, bad, ugly, and libav plugin packages for the media
formats the application needs.

## License

`webview_flutter_linux` is available under the BSD 3-Clause License. See
[`LICENSE`](LICENSE).
