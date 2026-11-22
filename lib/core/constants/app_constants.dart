/// Application-wide constants. The limits below are mandatory product rules and
/// are enforced in repositories AND by SQLite triggers (see docs/DATABASE.md).
abstract final class AppConstants {
  static const String appName = 'Tesla.org';
  static const String appVersion = '0.1.0';
  static const String buildNumber = '1';
  static const String databaseName = 'tesla_org.db';

  static const int maxAccountsPerPlatform = 10;
  static const int platformCount = 4;
  static const int maxAccountsTotal = maxAccountsPerPlatform * platformCount; // 40
  static const int maxTemplatesPerAccount = 20;
  static const int maxGroupLinksPerAccount = 20;
}
