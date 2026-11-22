import 'package:flutter_test/flutter_test.dart';
import 'package:tesla_org/core/logging/app_logger.dart';

void main() {
  test('redacts secrets in key/value and bearer forms', () {
    final out = AppLogger.redact('token=abc123 password: hunter2 Authorization: Bearer xyz.abc');
    expect(out.contains('abc123'), isFalse);
    expect(out.contains('hunter2'), isFalse);
    expect(out.contains('xyz.abc'), isFalse);
    expect(out.contains('[REDACTED]'), isTrue);
  });
}
