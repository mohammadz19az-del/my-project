import '../constants/app_constants.dart';

/// Raw SQL for migration 001 (schema version 1).
///
/// Migrations are append-only: never edit a released migration, add a new one.
/// Enum literals are hard-coded on purpose so a frozen migration never changes
/// when a Dart enum later evolves.
///
/// Every trigger is documented in docs/DATABASE.md.
final List<String> schemaV1Statements = <String>[
  // ---------------------------------------------------------------- tables
  """
CREATE TABLE accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  platform TEXT NOT NULL
    CHECK (platform IN ('telegram','whatsapp','rubika','soroush')),
  account_identifier TEXT NOT NULL CHECK (length(trim(account_identifier)) > 0),
  display_name TEXT,
  connection_status TEXT NOT NULL DEFAULT 'disconnected'
    CHECK (connection_status IN ('connected','disconnected','connecting',
      'authentication_required','credentials_expired','rate_limited',
      'unsupported','error','mock_connection')),
  credential_reference TEXT, -- key into secure storage; NEVER a secret itself
  capabilities_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  last_connected_at TEXT,
  last_activity_at TEXT,
  UNIQUE (platform, account_identifier)
)""",
  """
CREATE TABLE message_templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  title TEXT NOT NULL CHECK (length(trim(title)) > 0),
  body TEXT NOT NULL CHECK (length(trim(body)) > 0),
  language TEXT NOT NULL DEFAULT 'mixed'
    CHECK (language IN ('persian','english','mixed')),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE (account_id, title)
)""",
  """
CREATE TABLE group_links (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  platform TEXT NOT NULL
    CHECK (platform IN ('telegram','whatsapp','rubika','soroush')),
  url TEXT NOT NULL CHECK (length(trim(url)) > 0),
  title TEXT,
  description TEXT,
  validation_status TEXT NOT NULL DEFAULT 'unknown'
    CHECK (validation_status IN ('invalid_format','valid_format','verified',
      'inaccessible','authorization_unavailable','unknown')),
  last_verified_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE (account_id, url)
)""",
  """
CREATE TABLE destinations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  platform_destination_id TEXT NOT NULL,
  display_name TEXT,
  destination_type TEXT NOT NULL DEFAULT 'other',
  authorization_status TEXT NOT NULL DEFAULT 'unknown'
    CHECK (authorization_status IN ('authorized','unauthorized','unknown')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE (account_id, platform_destination_id)
)""",
  // History is never silently deleted: campaigns RESTRICT account/template deletion.
  """
CREATE TABLE campaigns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL CHECK (length(trim(name)) > 0),
  account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
  template_id INTEGER NOT NULL REFERENCES message_templates(id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','scheduled','running','paused','completed',
      'cancelled','failed')),
  schedule_start TEXT,
  schedule_end TEXT,
  timezone TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  started_at TEXT,
  completed_at TEXT,
  CHECK (schedule_end IS NULL OR schedule_start IS NULL OR schedule_end >= schedule_start)
)""",
  """
CREATE TABLE campaign_destinations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  campaign_id INTEGER NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  destination_id INTEGER NOT NULL REFERENCES destinations(id) ON DELETE RESTRICT,
  consent_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (consent_status IN ('pending','granted','denied','revoked')),
  authorization_status TEXT NOT NULL DEFAULT 'unknown'
    CHECK (authorization_status IN ('authorized','unauthorized','unknown')),
  UNIQUE (campaign_id, destination_id)
)""",
  """
CREATE TABLE delivery_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  campaign_id INTEGER NOT NULL REFERENCES campaigns(id) ON DELETE RESTRICT,
  destination_id INTEGER NOT NULL REFERENCES destinations(id) ON DELETE RESTRICT,
  template_id INTEGER NOT NULL REFERENCES message_templates(id) ON DELETE RESTRICT,
  idempotency_key TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','sending','sent','delivered','failed','skipped')),
  platform_message_id TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  error_code TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  delivered_at TEXT
)""",
  """
CREATE TABLE activity_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_type TEXT NOT NULL,
  account_id INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
  campaign_id INTEGER REFERENCES campaigns(id) ON DELETE SET NULL,
  description TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'info'
    CHECK (severity IN ('info','warning','error','security')),
  metadata_json TEXT NOT NULL DEFAULT '{}', -- must never contain secrets
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
)""",
  """
CREATE TABLE application_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
)""",

  // --------------------------------------------------------------- indexes
  'CREATE INDEX idx_accounts_platform ON accounts(platform)',
  'CREATE INDEX idx_templates_account ON message_templates(account_id)',
  'CREATE INDEX idx_group_links_account ON group_links(account_id)',
  'CREATE INDEX idx_destinations_account ON destinations(account_id)',
  'CREATE INDEX idx_campaigns_account_status ON campaigns(account_id, status)',
  'CREATE INDEX idx_campaign_destinations_campaign ON campaign_destinations(campaign_id)',
  'CREATE INDEX idx_deliveries_campaign_status ON delivery_records(campaign_id, status)',
  'CREATE INDEX idx_events_created ON activity_events(created_at)',
  'CREATE INDEX idx_events_account ON activity_events(account_id)',
  'CREATE INDEX idx_events_campaign ON activity_events(campaign_id)',
  'CREATE INDEX idx_events_severity ON activity_events(severity)',

  // ------------------------------------------------ limit-enforcing triggers
  """
CREATE TRIGGER trg_accounts_limit_insert BEFORE INSERT ON accounts
WHEN (SELECT COUNT(*) FROM accounts WHERE platform = NEW.platform)
     >= ${AppConstants.maxAccountsPerPlatform}
BEGIN SELECT RAISE(ABORT, 'LIMIT_ACCOUNTS_PER_PLATFORM'); END""",
  """
CREATE TRIGGER trg_accounts_limit_platform_change BEFORE UPDATE OF platform ON accounts
WHEN NEW.platform != OLD.platform
 AND (SELECT COUNT(*) FROM accounts WHERE platform = NEW.platform)
     >= ${AppConstants.maxAccountsPerPlatform}
BEGIN SELECT RAISE(ABORT, 'LIMIT_ACCOUNTS_PER_PLATFORM'); END""",
  """
CREATE TRIGGER trg_templates_limit_insert BEFORE INSERT ON message_templates
WHEN (SELECT COUNT(*) FROM message_templates WHERE account_id = NEW.account_id)
     >= ${AppConstants.maxTemplatesPerAccount}
BEGIN SELECT RAISE(ABORT, 'LIMIT_TEMPLATES_PER_ACCOUNT'); END""",
  """
CREATE TRIGGER trg_templates_limit_move BEFORE UPDATE OF account_id ON message_templates
WHEN NEW.account_id != OLD.account_id
 AND (SELECT COUNT(*) FROM message_templates WHERE account_id = NEW.account_id)
     >= ${AppConstants.maxTemplatesPerAccount}
BEGIN SELECT RAISE(ABORT, 'LIMIT_TEMPLATES_PER_ACCOUNT'); END""",
  """
CREATE TRIGGER trg_group_links_limit_insert BEFORE INSERT ON group_links
WHEN (SELECT COUNT(*) FROM group_links WHERE account_id = NEW.account_id)
     >= ${AppConstants.maxGroupLinksPerAccount}
BEGIN SELECT RAISE(ABORT, 'LIMIT_GROUP_LINKS_PER_ACCOUNT'); END""",
  """
CREATE TRIGGER trg_group_links_limit_move BEFORE UPDATE OF account_id ON group_links
WHEN NEW.account_id != OLD.account_id
 AND (SELECT COUNT(*) FROM group_links WHERE account_id = NEW.account_id)
     >= ${AppConstants.maxGroupLinksPerAccount}
BEGIN SELECT RAISE(ABORT, 'LIMIT_GROUP_LINKS_PER_ACCOUNT'); END""",

  // ------------------------------------------- relationship-integrity triggers
  """
CREATE TRIGGER trg_group_links_platform_insert BEFORE INSERT ON group_links
WHEN NEW.platform != (SELECT platform FROM accounts WHERE id = NEW.account_id)
BEGIN SELECT RAISE(ABORT, 'GROUP_PLATFORM_MISMATCH'); END""",
  """
CREATE TRIGGER trg_group_links_platform_update BEFORE UPDATE OF platform, account_id ON group_links
WHEN NEW.platform != (SELECT platform FROM accounts WHERE id = NEW.account_id)
BEGIN SELECT RAISE(ABORT, 'GROUP_PLATFORM_MISMATCH'); END""",
  """
CREATE TRIGGER trg_campaigns_template_account_insert BEFORE INSERT ON campaigns
WHEN NEW.account_id != (SELECT account_id FROM message_templates WHERE id = NEW.template_id)
BEGIN SELECT RAISE(ABORT, 'CAMPAIGN_TEMPLATE_ACCOUNT_MISMATCH'); END""",
  """
CREATE TRIGGER trg_campaigns_template_account_update BEFORE UPDATE OF account_id, template_id ON campaigns
WHEN NEW.account_id != (SELECT account_id FROM message_templates WHERE id = NEW.template_id)
BEGIN SELECT RAISE(ABORT, 'CAMPAIGN_TEMPLATE_ACCOUNT_MISMATCH'); END""",
  """
CREATE TRIGGER trg_campaign_destinations_account BEFORE INSERT ON campaign_destinations
WHEN (SELECT account_id FROM destinations WHERE id = NEW.destination_id)
     != (SELECT account_id FROM campaigns WHERE id = NEW.campaign_id)
BEGIN SELECT RAISE(ABORT, 'CAMPAIGN_DESTINATION_ACCOUNT_MISMATCH'); END""",
  // Defence in depth for the "recipient consent" rule: a delivery record can
  // only exist for a destination whose consent is granted AND is authorized.
  """
CREATE TRIGGER trg_delivery_requires_consent BEFORE INSERT ON delivery_records
WHEN NOT EXISTS (
  SELECT 1 FROM campaign_destinations cd
  WHERE cd.campaign_id = NEW.campaign_id
    AND cd.destination_id = NEW.destination_id
    AND cd.consent_status = 'granted'
    AND cd.authorization_status = 'authorized')
BEGIN SELECT RAISE(ABORT, 'DELIVERY_CONSENT_REQUIRED'); END""",

  // ----------------------------------------------------- audit-log triggers
  """
CREATE TRIGGER trg_accounts_audit_insert AFTER INSERT ON accounts
BEGIN
  INSERT INTO activity_events (event_type, account_id, description, severity, metadata_json)
  VALUES ('account_created', NEW.id,
          'Account added: ' || NEW.platform || ' (#' || NEW.id || ')', 'info', '{}');
END""",
  """
CREATE TRIGGER trg_accounts_audit_status AFTER UPDATE OF connection_status ON accounts
WHEN NEW.connection_status != OLD.connection_status
BEGIN
  INSERT INTO activity_events (event_type, account_id, description, severity, metadata_json)
  VALUES ('account_connection_changed', NEW.id,
          'Account ' || NEW.platform || ' (#' || NEW.id || ') changed from '
            || OLD.connection_status || ' to ' || NEW.connection_status,
          CASE WHEN NEW.connection_status IN ('error','credentials_expired') THEN 'warning'
               ELSE 'info' END,
          '{"from":"' || OLD.connection_status || '","to":"' || NEW.connection_status || '"}');
END""",
  """
CREATE TRIGGER trg_accounts_audit_delete AFTER DELETE ON accounts
BEGIN
  INSERT INTO activity_events (event_type, account_id, description, severity, metadata_json)
  VALUES ('account_deleted', NULL,
          'Account removed: ' || OLD.platform || ' (#' || OLD.id || ')', 'info', '{}');
END""",

  // ----------------------------------------------- updated_at maintenance
  ..._touchTriggers(const [
    'accounts',
    'message_templates',
    'group_links',
    'campaigns',
    'delivery_records',
  ]),
];

/// Keeps `updated_at` correct even if a caller forgets to set it.
List<String> _touchTriggers(List<String> tables) => [
      for (final t in tables)
        """
CREATE TRIGGER trg_${t}_touch_updated_at AFTER UPDATE ON $t
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE $t SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = NEW.id;
END""",
    ];
