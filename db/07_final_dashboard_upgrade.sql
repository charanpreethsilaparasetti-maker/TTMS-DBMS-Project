USE ttms;

-- Adds only one new base table. Existing TTMS tables/views remain unchanged.
CREATE TABLE IF NOT EXISTS audit_logs (
    audit_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id      INT NULL,
    entity_type  VARCHAR(40) NOT NULL,
    entity_id    INT NULL,
    action       VARCHAR(40) NOT NULL,
    details      JSON NULL,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_audit_user
        FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    INDEX idx_audit_created (created_at),
    INDEX idx_audit_entity (entity_type, entity_id)
) ENGINE=InnoDB;

-- Helpful indexes for dashboard trend/history queries.
CREATE INDEX idx_readings_time ON traffic_readings(recorded_at);
CREATE INDEX idx_incidents_status_time ON incidents(status, reported_at);

-- Initial audit entry so the panel is not empty after migration.
INSERT INTO audit_logs (user_id, entity_type, entity_id, action, details)
VALUES (2, 'system', NULL, 'dashboard_upgrade', JSON_OBJECT('message', 'Final dashboard analytics enabled'));

SELECT TABLE_NAME, TABLE_TYPE
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'ttms'
ORDER BY TABLE_TYPE, TABLE_NAME;

SELECT * FROM audit_logs ORDER BY created_at DESC, audit_id DESC LIMIT 20;
