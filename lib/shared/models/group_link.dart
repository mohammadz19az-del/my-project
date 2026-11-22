import '../../core/utilities/time.dart';
import '../enums/enums.dart';

class GroupLink {
  const GroupLink({
    required this.id,
    required this.accountId,
    required this.platform,
    required this.url,
    required this.validationStatus,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.description,
    this.lastVerifiedAt,
  });

  final int id;
  final int accountId;
  final MessagingPlatform platform;
  final String url;
  final String? title;
  final String? description;
  final ValidationStatus validationStatus;
  final DateTime? lastVerifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory GroupLink.fromMap(Map<String, Object?> m) => GroupLink(
        id: m['id']! as int,
        accountId: m['account_id']! as int,
        platform: enumFromDb(MessagingPlatform.values, m['platform']),
        url: m['url']! as String,
        title: m['title'] as String?,
        description: m['description'] as String?,
        validationStatus: enumFromDb(ValidationStatus.values, m['validation_status'],
            fallback: ValidationStatus.unknown),
        lastVerifiedAt: parseDate(m['last_verified_at']),
        createdAt: DateTime.parse(m['created_at']! as String),
        updatedAt: DateTime.parse(m['updated_at']! as String),
      );
}

class GroupLinkInput {
  const GroupLinkInput({
    required this.accountId,
    required this.url,
    this.title,
    this.description,
  });

  final int accountId;
  final String url;
  final String? title;
  final String? description;
}
