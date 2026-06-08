import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserNotifier extends Notifier<String> {
  @override
  String build() => 'me';

  void setUsername(String username) => state = username;
}

final userProvider = NotifierProvider<UserNotifier, String>(UserNotifier.new);
