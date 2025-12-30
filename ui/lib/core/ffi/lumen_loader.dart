import 'dart:ffi';
import 'dart:io';
import 'package:path/path.dart' as p;

DynamicLibrary loadLumenLibrary() {
  final exePath = Platform.resolvedExecutable;
  final exeDir = p.dirname(exePath);

  // Case 1: Running from a built bundle
  // exePath = <bundle>/Lumen
  final bundleLib1 = p.join(exeDir, 'lib', _libName());

  // Case 2: Running from flutter run (debug)
  // exePath = <bundle>/data/flutter_assets/kernel_blob.bin
  final assetsDir = p.dirname(exePath);
  final dataDir = p.dirname(assetsDir);
  final bundleDir = p.dirname(dataDir);
  final bundleLib2 = p.join(bundleDir, 'lib', _libName());

  // Case 3: Your script layout: <exeDir>/debug/bundle/lib/
  final bundleLib3 = p.join(exeDir, 'debug', 'bundle', 'lib', _libName());

  final candidates = [
    bundleLib1,
    bundleLib2,
    bundleLib3,
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) {
      return DynamicLibrary.open(path);
    }
  }

  throw ArgumentError(
    'Failed to find lumen_core library.\n'
    'Checked:\n${candidates.join('\n')}',
  );
}

String _libName() {
  if (Platform.isLinux) return 'liblumen_core.so';
  if (Platform.isMacOS) return 'liblumen_core.dylib';
  if (Platform.isWindows) return 'lumen_core.dll';
  throw UnsupportedError('Unsupported platform');
}
