import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserState {
  final String currentUser;
  final List<String> allUsers;

  UserState({required this.currentUser, required this.allUsers});

  UserState copyWith({String? currentUser, List<String>? allUsers}) {
    return UserState(
      currentUser: currentUser ?? this.currentUser,
      allUsers: allUsers ?? this.allUsers,
    );
  }
}

class UserNotifier extends Notifier<UserState> {
  static const _prefKey = 'last_user';

  @override
  UserState build() {
    // We'll initialize with a default, then load from prefs asynchronously
    _loadFromPrefs();
    return UserState(currentUser: 'me', allUsers: ['me']);
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUser = prefs.getString(_prefKey);
    final allUsers = prefs.getStringList('all_users') ?? ['me'];
    
    if (lastUser != null && allUsers.contains(lastUser)) {
      state = state.copyWith(currentUser: lastUser, allUsers: allUsers);
    } else {
      state = state.copyWith(allUsers: allUsers);
    }
  }

  Future<void> setUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, username);
    
    List<String> updatedAll = List.from(state.allUsers);
    if (!updatedAll.contains(username)) {
      updatedAll.add(username);
      await prefs.setStringList('all_users', updatedAll);
    }
    
    state = state.copyWith(currentUser: username, allUsers: updatedAll);
  }

  Future<void> addUser(String username) async {
    List<String> updatedAll = List.from(state.allUsers);
    if (!updatedAll.contains(username)) {
      updatedAll.add(username);
      state = state.copyWith(allUsers: updatedAll);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('all_users', updatedAll);
    }
  }
  
  void updateAvailableUsers(List<String> users) {
    List<String> updatedAll = List.from(state.allUsers);
    bool changed = false;
    for (var u in users) {
      if (!updatedAll.contains(u)) {
        updatedAll.add(u);
        changed = true;
      }
    }
    if (changed) {
      state = state.copyWith(allUsers: updatedAll);
      SharedPreferences.getInstance().then((p) => p.setStringList('all_users', updatedAll));
    }
  }
}

final userProvider = NotifierProvider<UserNotifier, UserState>(UserNotifier.new);
