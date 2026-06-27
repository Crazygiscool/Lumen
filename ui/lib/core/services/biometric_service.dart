import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Service for platform biometric authentication.
///
/// Uses platform channels to invoke biometric prompts
/// (Windows Hello, macOS Touch ID, Linux libsecret/pam).
///
/// NOTE: This is a deferred feature — the platform channel
/// handlers and native implementations are not yet complete.
/// See docs/roadmap.md Phase 5 for details.
class BiometricService {
  static const _channel = MethodChannel('lumen/biometric');

  /// Whether biometric authentication is available on this device.
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Authenticate the user via biometric prompt.
  /// Returns true if the user was successfully authenticated.
  Future<bool> authenticate({String reason = 'Unlock Lumen'}) async {
    try {
      return await _channel.invokeMethod('authenticate', {'reason': reason})
          as bool? ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Store encrypted session data to the platform keychain.
  Future<bool> storeKey(String keyId, Uint8List keyData) async {
    try {
      return await _channel.invokeMethod('storeKey', {
        'keyId': keyId,
        'keyData': base64Encode(keyData),
      }) as bool? ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Retrieve encrypted session data from the platform keychain.
  Future<Uint8List?> retrieveKey(String keyId) async {
    try {
      final result = await _channel.invokeMethod('retrieveKey', {
        'keyId': keyId,
      }) as String?;
      if (result != null) {
        return base64Decode(result);
      }
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Delete a stored key from the platform keychain.
  Future<bool> deleteKey(String keyId) async {
    try {
      return await _channel.invokeMethod('deleteKey', {'keyId': keyId})
          as bool? ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
