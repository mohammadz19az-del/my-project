/// Migration 003: campaign sending options and WhatsApp template fields.
/// ADD COLUMN keeps all existing rows (defaults apply), so user data is preserved.
final List<String> schemaV3Statements = <String>[
  'ALTER TABLE campaigns ADD COLUMN send_interval_seconds INTEGER NOT NULL DEFAULT 5 '
      'CHECK (send_interval_seconds >= 1)',
  'ALTER TABLE campaigns ADD COLUMN rounds INTEGER NOT NULL DEFAULT 1 '
      'CHECK (rounds BETWEEN 1 AND 5)',
  'ALTER TABLE campaigns ADD COLUMN max_deliveries INTEGER '
      'CHECK (max_deliveries IS NULL OR max_deliveries >= 1)',
  // Name/language of a Meta-approved WhatsApp template (business-initiated messages).
  'ALTER TABLE message_templates ADD COLUMN wa_template_name TEXT',
  'ALTER TABLE message_templates ADD COLUMN wa_template_language TEXT',
];
