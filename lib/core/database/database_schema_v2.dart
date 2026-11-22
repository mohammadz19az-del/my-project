/// Migration 002: audit triggers for campaigns, so campaign lifecycle events
/// reach `activity_events` regardless of which code path changes a campaign.
/// Descriptions carry ids only (campaign names are never copied into the log).
final List<String> schemaV2Statements = <String>[
  """
CREATE TRIGGER trg_campaigns_audit_insert AFTER INSERT ON campaigns
BEGIN
  INSERT INTO activity_events (event_type, account_id, campaign_id, description, severity, metadata_json)
  VALUES ('campaign_created', NEW.account_id, NEW.id,
          'Campaign created (#' || NEW.id || ')', 'info', '{}');
END""",
  """
CREATE TRIGGER trg_campaigns_audit_status AFTER UPDATE OF status ON campaigns
WHEN NEW.status != OLD.status
BEGIN
  INSERT INTO activity_events (event_type, account_id, campaign_id, description, severity, metadata_json)
  VALUES ('campaign_status_changed', NEW.account_id, NEW.id,
          'Campaign #' || NEW.id || ' changed from ' || OLD.status || ' to ' || NEW.status,
          CASE WHEN NEW.status = 'failed' THEN 'error' ELSE 'info' END,
          '{"from":"' || OLD.status || '","to":"' || NEW.status || '"}');
END""",
  'CREATE INDEX idx_deliveries_destination ON delivery_records(destination_id)',
];
