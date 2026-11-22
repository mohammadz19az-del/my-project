# Tesla.org — documentation

## 1. Architecture
Feature-oriented Flutter app. Riverpod (state), GoRouter (navigation, shell with sidebar ≥ 900 px / drawer),
`sqflite` + raw SQL (FFI on Windows). Layers: `presentation` (screens) → `application` (services,
engine, providers) → `data` (repositories) → SQLite. Messaging platforms sit behind `PlatformAdapter`
(`lib/integrations/common`). No dependencies were added beyond Riverpod, GoRouter, sqflite(+ffi),
path/path_provider, flutter_secure_storage and intl; HTTP uses `dart:io`, clipboard uses Flutter services.

## 2. Messaging integrations (official APIs only)
| Platform | Adapter | Facts the code relies on (verified against official docs when written) |
|---|---|---|
| Telegram | `TelegramAdapter` | Bot API: `getMe` (connect, token must belong to the stored `@username`), `sendMessage`, `getChat` for public `@username` links. 429 → `retry_after` is honoured. Limits: ~1 msg/s per chat, ≤ 20 msg/min per group (min interval set to 3 s), text ≤ 4096. Bots cannot start conversations and cannot join via links; private invite links cannot be resolved. No delivery receipts. |
| WhatsApp | `WhatsAppAdapter` | Cloud API: `GET /{phone-number-id}?fields=…` (connect), `POST /{phone-number-id}/messages` with `Authorization: Bearer`. Numbers in E.164 with `+`. Free text only inside the 24-hour window; otherwise a Meta-approved template (`wa_template_name` + language). Recipients must have opted in. Delivery/read status needs webhooks → **not available** in this app. Graph version constant: `WhatsAppAdapter.graphVersion` (update when Meta retires it). |
| Rubika / Soroush | `MockPlatformAdapter` | No official API verified. Connect = `Mock connection`; every send = *simulated* (recorded as "skipped/simulated", never "sent"). Integration point: replace the adapter in `adapter_registry_provider.dart`. |

Capability matrix per platform: Settings → Integration status. "Production readiness" is `not verified`
for Telegram and `requires approval` for WhatsApp: the code has never been run against live accounts.

## 3. Campaign engine (`campaign_engine.dart`)
Pre-flight (account connected, credentials present, template enabled and short enough, interval ≥ platform
minimum, schedule not over, ≥ 1 destination with consent + authorization) → worker loop. Before **every**
send the destination's consent/authorization is re-read from the database (revocation takes effect
immediately). One delivery record per `(campaign, destination, template, round)` idempotency key; existing
non-pending records are never re-sent. Temporary errors retry up to 3 times; rate limits wait `retry_after`
and, after 3 hits, pause the campaign; rejected credentials pause it and flag the account. Intervals are
fixed (no randomisation), one account per campaign (no rotation).
**Background limits:** the worker lives inside the app process. If the app closes, `recover()` pauses
campaigns that were running at the next start. Scheduled starts are checked every 20 s while the app is open.
There is no Android foreground service and no Windows background service.

## 4. Security
* Tokens: `flutter_secure_storage` (Android: encrypted preferences with a Keystore-backed key; Windows:
  the plugin's protected storage — verify its exact guarantees for your threat model). SQLite stores only
  a random reference. Secrets are never logged (logger redacts `token=…`, `Bearer …`), exported or backed up.
* HTTPS only, default certificate validation, 20 s timeouts; URLs (which contain the Telegram token) are never logged.
* **Not protected:** the SQLite database and backup/export files are plain files (templates, links,
  destinations, history). No app lock/PIN. Protect the device account.
* Consent is the operator's attestation; the app can only enforce that it was recorded.

## 5. Notifications
In-app notices only (snackbars while the app is open) for campaign completion, errors/automatic pauses and
rejected credentials. OS notifications are not implemented.

## 6. Backup, export
Settings → Backup & restore (JSON, no credentials) and Reports → CSV/JSON export (UTF-8 with BOM for Excel).
Files go to `<Documents>/TeslaOrg/{backups,exports}`. On Android that folder is private to the app: use the
**Copy data** buttons to move content elsewhere. PDF export and OS file pickers are not implemented.

## 7. Troubleshooting
| Symptom | Cause / fix |
|---|---|
| Android build: "minSdkVersion 21 cannot be smaller than 23" | run `scripts\setup.ps1` or set `minSdk = 23` |
| Android release app cannot reach the internet | INTERNET permission missing from the main manifest (script adds it) |
| `flutter test` fails on `widget_test.dart` | delete that file (created by `flutter create`) |
| Windows build error about Visual Studio | install the *Desktop development with C++* workload |
| Telegram "Connect" → *Authentication required* | wrong/revoked token; token and `@username` must belong to the same bot |
| Telegram send → `TG_403` / `TG_400` | the recipient never started the bot / blocked it / chat not found |
| WhatsApp send → `WA_131047` | outside the 24-hour window: use an approved template name |
| WhatsApp connect → *Credentials expired* | token expired; create a permanent system-user token |
| Persian text looks wrong | optional: bundle Vazirmatn (README) |
| Campaign shows "Interrupted" | the app was closed while it ran; press Resume |
