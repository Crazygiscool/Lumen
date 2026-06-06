import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../lumen_core.dart';

final lumenCoreProvider = Provider<LumenCore>((ref) {
  return LumenCore();
});
