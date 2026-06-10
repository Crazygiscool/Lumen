import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole {
  admin,
  member;

  String toJson() => name;
  static UserRole fromJson(String json) => values.byName(json);
}

class UserProfile {
  final String username;
  final UserRole role;

  UserProfile({required this.username, required this.role});

  Map<String, dynamic> toMap() => {
    'username': username,
    'role': role.toJson(),
  };

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile(
    username: map['username'],
    role: UserRole.fromJson(map['role']),
  );
}

class UserState {
  final String? currentUser;
  final List<UserProfile> allUsers;

  UserState({this.currentUser, required this.allUsers});

  UserState copyWith({String? currentUser, List<UserProfile>? allUsers}) {
    return UserState(
      currentUser: currentUser ?? this.currentUser,
      allUsers: allUsers ?? this.allUsers,
    );
  }

  bool get isAdmin => allUsers.any((u) => u.username == currentUser && u.role == UserRole.admin);
}

class UserNotifier extends Notifier<UserState> {
  static const _prefKey = 'last_user';
  static const _usersKey = 'user_profiles';

  @override
  UserState build() {
    _loadFromPrefs();
    return UserState(allUsers: []);
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUser = prefs.getString(_prefKey);
    final usersJson = prefs.getStringList(_usersKey);
    
    List<UserProfile> loadedUsers = [];
    if (usersJson != null) {
      loadedUsers = usersJson.map((j) => UserProfile.fromMap(jsonDecode(j))).toList();
    }
    
    if (lastUser != null && loadedUsers.any((u) => u.username == lastUser)) {
      state = UserState(currentUser: lastUser, allUsers: loadedUsers);
    } else {
      state = UserState(
        currentUser: loadedUsers.isNotEmpty ? loadedUsers.first.username : null, 
        allUsers: loadedUsers
      );
    }
  }

  Future<void> setUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, username);
    
    if (!state.allUsers.any((u) => u.username == username)) {
      await addUser(username);
    }
    
    state = state.copyWith(currentUser: username);
  }

  Future<void> addUser(String username) async {
    List<UserProfile> updatedAll = List.from(state.allUsers);
    if (!updatedAll.any((u) => u.username == username)) {
      // First user is Admin, others are Members
      final role = updatedAll.isEmpty ? UserRole.admin : UserRole.member;
      updatedAll.add(UserProfile(username: username, role: role));
      
      state = state.copyWith(allUsers: updatedAll);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_usersKey, updatedAll.map((u) => jsonEncode(u.toMap())).toList());
    }
  }
  
  void updateAvailableUsers(List<String> usernames) {
    List<UserProfile> updatedAll = List.from(state.allUsers);
    bool changed = false;
    for (var name in usernames) {
      if (name == 'me' || name == 'stoic-import') continue; // Skip generic authors
      if (!updatedAll.any((u) => u.username == name)) {
        final role = updatedAll.isEmpty ? UserRole.admin : UserRole.member;
        updatedAll.add(UserProfile(username: name, role: role));
        changed = true;
      }
    }
    if (changed) {
      state = state.copyWith(allUsers: updatedAll);
      SharedPreferences.getInstance().then((p) {
        p.setStringList(_usersKey, updatedAll.map((u) => jsonEncode(u.toMap())).toList());
      });
    }
  }
}

final userProvider = NotifierProvider<UserNotifier, UserState>(UserNotifier.new);
