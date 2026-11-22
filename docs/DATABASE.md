# Tesla.org — Database

SQLite via `sqflite` (Android) / `sqflite_common_ffi` (Windows), **raw SQL**, forward-only
migrations, repositories. Schema version: **3**. Sources: `lib/core/database/`.

* `PRAGMA foreign_keys = ON` is set in `onConfigure`.
* Migrations are append-only (`migrations.dart`). Opening a database **newer** than the app
  throws and leaves the file untouched (never destructive).
* Timestamps are ISO-8601 UTC text. Enum values are snake_case text with CHECK constraints.
* No secrets are stored: `accounts.credential_reference` is only a key into secure storage.

## Tables (v1)
`accounts`, `message_templates`, `group_links`, `destinations`, `campaigns`,
`campaign_destinations`, `delivery_records`, `activity_events`, `application_settings`.

Deletion policy: campaigns / deliveries `RESTRICT` deletion of accounts, templates and
destinations, so **campaign history is never silently deleted**. Templates, group links and
destinations cascade with their account. `activity_events` references are `SET NULL`.

## Triggers — purpose of each
| Trigger | Purpose |
|---|---|
| `trg_accounts_limit_insert`, `trg_accounts_limit_platform_change` | Max **10 accounts per platform** (4 platforms ⇒ 40 total), even if a caller bypasses the repository. |
| `trg_templates_limit_insert`, `trg_templates_limit_move` | Max **20 templates per account**. |
| `trg_group_links_limit_insert`, `trg_group_links_limit_move` | Max **20 group links per account**. |
| `trg_group_links_platform_insert/update` | A group link's platform must equal its account's platform. |
| `trg_campaigns_template_account_insert/update` | A campaign's template must belong to the campaign's account. |
| `trg_campaign_destinations_account` | A campaign's destination must belong to the campaign's account. |
| `trg_delivery_requires_consent` | A delivery record can exist only for a destination with `consent_status='granted'` **and** `authorization_status='authorized'`. |
| `trg_accounts_audit_insert/status/delete` | Writes `activity_events` rows for account creation, connection-status changes and deletion (descriptions contain platform and id only, no identifiers). |
| `trg_campaigns_audit_insert/status` (migration 002) | Writes `activity_events` rows for campaign creation and every status change (ids only; `failed` is logged with severity `error`). |
| `trg_<table>_touch_updated_at` | Keeps `updated_at` current on accounts, templates, group links, campaigns, deliveries. |

Trigger failures raise `RAISE(ABORT, '<CODE>')`; `db_guard.dart` maps each code to a typed
`AppException` that the UI localizes.

## Verification status
The SQL was executed against a real SQLite engine (Python `sqlite3`) in the build
environment to check syntax and every trigger rule listed above. The Dart code itself has
**not** been compiled or run.

## Migration history
| Version | Content |
|---|---|
| 1 | Initial schema: 9 tables, indexes, limit/integrity/audit triggers |
| 2 | Campaign audit triggers, `idx_deliveries_destination` |
| 3 | `campaigns.send_interval_seconds` (>=1), `rounds` (1-5), `max_deliveries`; `message_templates.wa_template_name/_language` (ADD COLUMN, existing rows keep defaults) |

## Repository rules added in Phase 3
* **Group links**: platform is taken from the owning account. Only an offline *format* check
  runs (`LinkValidator`); the stored status is `valid_format`/`invalid_format`, never `verified`
  without an authorized platform check. Editing a URL clears prior verification.
* **Campaigns**: transition table enforced in `SqliteCampaignRepository.canTransition`
  (terminal: completed, cancelled, failed). Only drafts can be edited/deleted.
  Consent can be revoked in any status.
* **Deliveries**: `createOrGet` is idempotent on `idempotency_key`; the consent trigger rejects
  records without granted consent + authorized destination; error text is redacted and truncated;
  `recoverInterrupted()` resets `sending` records to `pending` after a restart.

## Backup / restore (Phase 10)
`BackupService` exports every table to JSON (credentials and `credential_reference` are blanked).
Restore validates format, schema version (<= current) and column names, writes a safety backup,
then replaces all data in ONE transaction (any trigger violation rolls everything back). Audit
triggers that fire during restore are discarded and the backed-up `activity_events` are restored.
