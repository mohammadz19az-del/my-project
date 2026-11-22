import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/core/security/credential_store.dart';
import 'package:tesla_org/integrations/common/platform_adapter.dart';
import 'package:tesla_org/shared/enums/enums.dart';

void main() {
  test('in-memory store round-trips and deletes', () async {
    final store = InMemoryCredentialStore();
    await store.write('ref', {'bot_token': 'secret'});
    expect(await store.contains('ref'), isTrue);
    expect((await store.read('ref'))!['bot_token'], 'secret');
    // returned maps are copies
    (await store.read('ref'))!['bot_token'] = 'changed';
    expect((await store.read('ref'))!['bot_token'], 'secret');
    await store.delete('ref');
    expect(await store.contains('ref'), isFalse);
    expect(await store.read('ref'), isNull);
  });

  test('references are opaque, prefixed and unique', () {
    final rng = Random(1);
    final a = newCredentialReference(MessagingPlatform.telegram, random: rng);
    final b = newCredentialReference(MessagingPlatform.telegram, random: rng);
    expect(a, isNot(b));
    expect(a.startsWith('cred_telegram_'), isTrue);
    expect(RegExp(r'^cred_telegram_[0-9a-f]{32}$').hasMatch(a), isTrue);
  });

  test('credentials never reveal values when printed', () {
    const c = AccountCredentials({'bot_token': 'SUPER-SECRET'});
    expect('$c'.contains('SUPER-SECRET'), isFalse);
  });
}
