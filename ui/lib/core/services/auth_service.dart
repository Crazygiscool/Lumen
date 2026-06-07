import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../lumen_core.dart';
import 'core_provider.dart';

class AuthNotifier extends Notifier<bool> {
  late final LumenCore _lumen;

  @override
  bool build() {
    _lumen = ref.read(lumenCoreProvider);
    return _lumen.isUnlocked();
  }

  bool unlock(String password) {
    final ok = _lumen.unlock(password);
    if (ok) state = true;
    return ok;
  }

  void lock() {
    _lumen.lock();
    state = false;
  }

  bool hasPassword() {
    return _lumen.hasPassword();
  }

  bool setPassword(String password) {
    final ok = _lumen.setPassword(password);
    if (ok) state = true;
    return ok;
  }

  bool get isUnlocked => state;
}

final authProvider = NotifierProvider<AuthNotifier, bool>(AuthNotifier.new);
