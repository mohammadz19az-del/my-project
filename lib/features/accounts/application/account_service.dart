import '../../../core/errors/app_exception.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/security/credential_store.dart';
import '../../../integrations/common/platform_adapter.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/account.dart';
import '../../../shared/models/activity_event.dart';
import '../../reports/data/activity_repository.dart';
import '../data/account_repository.dart';
import '../domain/account_validator.dart';
import '../domain/platform_specs.dart';

class AccountDraft {
  const AccountDraft({
    required this.platform,
    required this.identifier,
    this.displayName,
    this.secrets = const {},
  });

  final MessagingPlatform platform;
  final String identifier;
  final String? displayName;

  /// Secret values keyed by [SecretField.key]; never logged or stored in SQLite.
  final Map<String, String> secrets;
}

/// Account use-cases: coordinates SQLite (metadata), secure storage (secrets)
/// and platform adapters (connections), keeping the three consistent.
class AccountService {
  AccountService({
    required AccountRepository accounts,
    required CredentialStore store,
    required AdapterRegistry registry,
    required ActivityRepository activity,
  })  : _accounts = accounts,
        _store = store,
        _registry = registry,
        _activity = activity;

  final AccountRepository _accounts;
  final CredentialStore _store;
  final AdapterRegistry _registry;
  final ActivityRepository _activity;

  static bool isLive(ConnectionStatus s) =>
      s == ConnectionStatus.connected ||
      s == ConnectionStatus.mockConnection ||
      s == ConnectionStatus.connecting;

  AdapterMode modeFor(MessagingPlatform p) => _registry.forPlatform(p).mode;

  Future<bool> hasStoredCredentials(Account account) async {
    final ref = account.credentialReference;
    if (ref == null) return false;
    return _store.contains(ref);
  }

  void _validate(
    MessagingPlatform platform,
    String identifier,
    Map<String, String> secrets, {
    required bool secretsRequired,
  }) {
    const invalid = ValidationException(
        ErrorCodes.invalidAccountInput, 'Account details failed validation.');
    if (AccountValidator.validateIdentifier(platform, identifier) != null) throw invalid;
    for (final field in PlatformSpecs.of(platform).secrets) {
      final value = secrets[field.key]?.trim() ?? '';
      if (value.isEmpty) {
        if (secretsRequired) throw invalid;
        continue;
      }
      if (AccountValidator.validateSecret(platform, field.key, value) != null) throw invalid;
    }
  }

  Future<Account> _require(int id) async {
    final a = await _accounts.getById(id);
    if (a == null) throw const NotFoundException('Account not found.');
    return a;
  }

  /// Secret is written first; if the database rejects the account (limit,
  /// duplicate, ...) the secret is removed again so nothing is left orphaned.
  Future<Account> create(AccountDraft draft) async {
    _validate(draft.platform, draft.identifier, draft.secrets, secretsRequired: true);
    final spec = PlatformSpecs.of(draft.platform);
    final identifier = AccountValidator.normalizeIdentifier(draft.platform, draft.identifier);

    String? reference;
    if (spec.requiresCredentials) {
      reference = newCredentialReference(draft.platform);
      await _store.write(reference, {
        for (final f in spec.secrets) f.key: draft.secrets[f.key]!.trim(),
      });
    }
    try {
      return await _accounts.create(AccountInput(
        platform: draft.platform,
        accountIdentifier: identifier,
        displayName: draft.displayName,
        credentialReference: reference,
      ));
    } catch (_) {
      if (reference != null) await _deleteSecretQuietly(reference);
      rethrow;
    }
  }

  /// Blank secret values keep the stored ones. Changing the identifier or a
  /// secret of a live connection disconnects it first so the status stays truthful.
  Future<Account> update(
    int id, {
    required String identifier,
    String? displayName,
    Map<String, String> newSecrets = const {},
  }) async {
    final account = await _require(id);
    _validate(account.platform, identifier, newSecrets, secretsRequired: false);
    final normalized = AccountValidator.normalizeIdentifier(account.platform, identifier);
    final provided = {
      for (final e in newSecrets.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    };

    if ((provided.isNotEmpty || normalized != account.accountIdentifier) &&
        isLive(account.connectionStatus)) {
      await disconnect(id);
    }

    if (provided.isNotEmpty) {
      var ref = account.credentialReference;
      final isNew = ref == null;
      ref ??= newCredentialReference(account.platform);
      final existing = isNew ? <String, String>{} : (await _store.read(ref) ?? {});
      await _store.write(ref, {...existing, ...provided});
      if (isNew) await _accounts.setCredentialReference(id, ref);
    }
    return _accounts.updateDetails(id,
        accountIdentifier: normalized, displayName: displayName ?? '');
  }

  /// Database first (it may refuse, e.g. when campaign history exists); only then
  /// the adapter session and the stored secret are cleaned up.
  Future<void> delete(int id) async {
    final account = await _require(id);
    await _accounts.delete(id);
    if (isLive(account.connectionStatus)) {
      try {
        await _registry
            .forPlatform(account.platform)
            .disconnect(accountIdentifier: account.accountIdentifier);
      } catch (e) {
        AppLogger.warning('Adapter disconnect failed while deleting an account');
      }
    }
    final ref = account.credentialReference;
    if (ref != null) await _deleteSecretQuietly(ref);
  }

  Future<Account> connect(int id) async {
    final account = await _require(id);
    final spec = PlatformSpecs.of(account.platform);
    final adapter = _registry.forPlatform(account.platform);

    var credentials = const AccountCredentials({});
    if (spec.requiresCredentials) {
      final ref = account.credentialReference;
      final stored = ref == null ? null : await _store.read(ref);
      final complete = stored != null && spec.secrets.every((f) => (stored[f.key] ?? '').isNotEmpty);
      if (!complete) {
        await _accounts.updateConnectionStatus(id, ConnectionStatus.authenticationRequired);
        await _logFailure(account, 'CREDENTIALS_MISSING');
        return _require(id);
      }
      credentials = AccountCredentials(stored);
    }

    await _accounts.updateConnectionStatus(id, ConnectionStatus.connecting);
    ConnectResult result;
    try {
      result = await adapter.connect(
        accountIdentifier: account.accountIdentifier,
        credentials: credentials,
      );
    } catch (e, s) {
      AppLogger.error('Adapter connect failed', error: e.runtimeType, stackTrace: s);
      result = const ConnectResult(ConnectionStatus.error, errorCode: 'ADAPTER_EXCEPTION');
    }

    await _accounts.updateConnectionStatus(id, result.status);
    if (result.displayName != null && account.displayName == null) {
      await _accounts.updateDetails(id, displayName: result.displayName);
    }
    if (result.status == ConnectionStatus.connected ||
        result.status == ConnectionStatus.mockConnection) {
      await _accounts.touchActivity(id);
    }
    if (result.errorCode != null) await _logFailure(account, result.errorCode!);
    return _require(id);
  }

  /// Authorized group-link lookup through the account's adapter. Without stored
  /// credentials (or on any failure) the result is never `verified`.
  Future<GroupCheck> checkGroupLink(Account account, String url) async {
    final spec = PlatformSpecs.of(account.platform);
    var credentials = const AccountCredentials({});
    if (spec.requiresCredentials) {
      final ref = account.credentialReference;
      final stored = ref == null ? null : await _store.read(ref);
      if (stored == null) return const GroupCheck(ValidationStatus.authorizationUnavailable);
      credentials = AccountCredentials(stored);
    }
    try {
      return await _registry
          .forPlatform(account.platform)
          .checkGroupLink(credentials: credentials, url: url);
    } catch (_) {
      return const GroupCheck(ValidationStatus.unknown);
    }
  }

  Future<Account> disconnect(int id) async {
    final account = await _require(id);
    try {
      await _registry
          .forPlatform(account.platform)
          .disconnect(accountIdentifier: account.accountIdentifier);
    } catch (e) {
      AppLogger.warning('Adapter disconnect failed');
    }
    await _accounts.updateConnectionStatus(id, ConnectionStatus.disconnected);
    return _require(id);
  }

  Future<void> _logFailure(Account account, String code) => _activity.log(ActivityEventInput(
        eventType: 'account_connect_failed',
        description: 'Connection attempt failed for ${account.platform.name} (#${account.id})',
        severity: EventSeverity.warning,
        accountId: account.id,
        metadata: {'code': code},
      ));

  Future<void> _deleteSecretQuietly(String reference) async {
    try {
      await _store.delete(reference);
    } catch (_) {
      AppLogger.warning('Could not remove a stored credential entry');
    }
  }
}
