import '../enums/enums.dart';

class MessageTemplate {
  const MessageTemplate({
    required this.id,
    required this.accountId,
    required this.title,
    required this.body,
    required this.language,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.waTemplateName,
    this.waTemplateLanguage,
  });

  final int id;
  final int accountId;
  final String title;

  /// WhatsApp only: Meta-approved template used for business-initiated messages.
  final String? waTemplateName;
  final String? waTemplateLanguage;

  /// Stored exactly as the user typed it (no trimming or normalisation).
  final String body;
  final MessageLanguage language;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MessageTemplate.fromMap(Map<String, Object?> m) => MessageTemplate(
        id: m['id']! as int,
        accountId: m['account_id']! as int,
        title: m['title']! as String,
        body: m['body']! as String,
        language: enumFromDb(MessageLanguage.values, m['language'],
            fallback: MessageLanguage.mixed),
        enabled: (m['enabled']! as int) == 1,
        createdAt: DateTime.parse(m['created_at']! as String),
        updatedAt: DateTime.parse(m['updated_at']! as String),
        waTemplateName: m['wa_template_name'] as String?,
        waTemplateLanguage: m['wa_template_language'] as String?,
      );
}

class MessageTemplateInput {
  const MessageTemplateInput({
    required this.accountId,
    required this.title,
    required this.body,
    this.language = MessageLanguage.mixed,
    this.enabled = true,
    this.waTemplateName,
    this.waTemplateLanguage,
  });

  final String? waTemplateName;
  final String? waTemplateLanguage;

  final int accountId;
  final String title;
  final String body;
  final MessageLanguage language;
  final bool enabled;
}
