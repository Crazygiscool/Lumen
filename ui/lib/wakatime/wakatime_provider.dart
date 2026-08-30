import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'wakatime_service.dart';

final wakatimeServiceProvider = Provider<WakatimeService>((ref) {
  return WakatimeService();
});

@immutable
class WakatimeState {
  const WakatimeState({
    this.active = false,
    this.stats,
    this.user,
    this.error,
  });

  /// True when a key is configured (regardless of fetch success).
  final bool active;
  final WakatimeStats? stats;
  final String? user;
  final String? error;

  WakatimeState copyWith({
    bool? active,
    WakatimeStats? stats,
    String? user,
    String? error,
    bool clearError = false,
  }) => WakatimeState(
    active: active ?? this.active,
    stats: stats ?? this.stats,
    user: user ?? this.user,
    error: clearError ? null : (error ?? this.error),
  );
}

class WakatimeNotifier extends AsyncNotifier<WakatimeState> {
  @override
  Future<WakatimeState> build() async {
    final key = ref.watch(settingsProvider).wakaApiKey;
    if (key == null || key.trim().isEmpty) {
      return const WakatimeState();
    }
    try {
      final service = ref.watch(wakatimeServiceProvider);
      final user = await service.user(key);
      final stats = await service.stats(key);
      return WakatimeState(active: true, user: user, stats: stats);
    } catch (e) {
      return WakatimeState(active: true, error: e.toString());
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final wakatimeProvider = AsyncNotifierProvider<WakatimeNotifier, WakatimeState>(
  WakatimeNotifier.new,
);