import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/enums/enums.dart';
import '../errors/app_exception.dart';
import '../logging/app_logger.dart';

/// Where account secrets (bot tokens, access tokens) live. SQLite only ever
/// stores the *reference* returned by [newCredentialReference].
abstract class CredentialStore {
  Future<void> write(String reference, Map<String, String> values);
  Future<Map<String, String>?> read(String reference);
  Future<bool> contains(String reference);
  Future<void> delete(String reference);
}

/// Opaque, random, non-identifying key for a secure-storage entry.
String newCredentialReference(MessagingPlatform platform, {Random? random}) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return 'cred_${platform.dbValue}_$hex';
}

/// Production store backed by `flutter_secure_storage`:
/// Android → encrypted preferences with a Keystore-backed key;
/// Windows → the plugin's protected storage. Exact guarantees are those of the plugin.
/// Errors are wrapped so no plugin message (which could echo data) reaches the UI.
class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const _prefix = 'tesla_org.cred.';

  Future<T> _guard<T>(String op, Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      AppLogger.error('Secure storage $op failed', error: e.runtimeType);
      throw CredentialStorageFailure('Secure storage $op failed.', cause: e.runtimeType);
    }
  }

  @override
  Future<void> write(String reference, Map<String, String> values) =>
      _guard('write', () => _storage.write(key: '$_prefix$reference', value: jsonEncode(values)));

  @override
  Future<Map<String, String>?> read(String reference) => _guard('read', () async {
        final raw = await _storage.read(key: '$_prefix$reference');
        if (raw == null) return null;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return decoded.map((k, v) => MapEntry(k, v as String));
      });

  @override
  Future<bool> contains(String reference) =>
      _guard('lookup', () => _storage.containsKey(key: '$_prefix$reference'));

  @override
  Future<void> delete(String reference) =>
      _guard('delete', () => _storage.delete(key: '$_prefix$reference'));
}

/// Non-persistent store for tests and previews. Never use in production.
class InMemoryCredentialStore implements CredentialStore {
  final Map<String, Map<String, String>> _data = {};

  int get length => _data.length;

  @override
  Future<void> write(String reference, Map<String, String> values) async =>
      _data[reference] = Map.of(values);

  @override
  Future<Map<String, String>?> read(String reference) async =>
      _data[reference] == null ? null : Map.of(_data[reference]!);

  @override
  Future<bool> contains(String reference) async => _data.containsKey(reference);

  @override
  Future<void> delete(String reference) async => _data.remove(reference);
}
