-- =====================================================================
-- Traffic & Transportation Management System (TTMS)  -  MySQL 8.0
-- DBMS Project | IIIT Bhopal | Monsoon 2026-27
-- Run the whole file in MySQL Workbench (or: mysql -u root -p < ttms_mysql.sql)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 8.1  DATABASE CREATION
-- ---------------------------------------------------------------------
DROP DATABASE IF EXISTS ttms;
CREATE DATABASE ttms CHARACTER SET utf8mb4;
USE ttms;

-- ---------------------------------------------------------------------
-- 8.2  TABLE CREATION  (13 relations, all in 3NF/BCNF)
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    role_id      INT AUTO_INCREMENT PRIMARY KEY,
    name         VARCHAR(50)  NOT NULL UNIQUE,
    description  VARCHAR(255)
) ENGINE=InnoDB;

CREATE TABLE users (
    user_id        INT AUTO_INCREMENT PRIMARY KEY,
    role_id        INT          NOT NULL,
    full_name      VARCHAR(120) NOT NULL,
    email          VARCHAR(160) NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL,
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES roles(role_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE intersections (
    intersection_id  INT AUTO_INCREMENT PRIMARY KEY,
    name             VARCHAR(150)  NOT NULL UNIQUE,
    latitude         DECIMAL(9,6)  NOT NULL,
    longitude        DECIMAL(9,6)  NOT NULL,
    CONSTRAINT chk_int_lat CHECK (latitude  BETWEEN -90  AND 90),
    CONSTRAINT chk_int_lng CHECK (longitude BETWEEN -180 AND 180)
) ENGINE=InnoDB;

CREATE TABLE road_segments (
    segment_id         INT AUTO_INCREMENT PRIMARY KEY,
    name               VARCHAR(150)  NOT NULL,
    road_class         VARCHAR(20)   NOT NULL,
    from_intersection  INT           NOT NULL,
    to_intersection    INT           NOT NULL,
    length_m           DECIMAL(10,2) NOT NULL,
    lanes              TINYINT       NOT NULL DEFAULT 2,
    speed_limit_kmh    SMALLINT      NOT NULL,
    is_one_way         BOOLEAN       NOT NULL DEFAULT FALSE,
    status             VARCHAR(20)   NOT NULL DEFAULT 'open',
    CONSTRAINT chk_seg_class  CHECK (road_class IN ('highway','arterial','collector','local')),
    CONSTRAINT chk_seg_status CHECK (status IN ('open','restricted','closed')),
    CONSTRAINT chk_seg_len    CHECK (length_m > 0),
    CONSTRAINT chk_seg_lanes  CHECK (lanes BETWEEN 1 AND 8),
    CONSTRAINT chk_seg_speed  CHECK (speed_limit_kmh BETWEEN 5 AND 130),
    CONSTRAINT chk_seg_ends   CHECK (from_intersection <> to_intersection),
    CONSTRAINT fk_seg_from FOREIGN KEY (from_intersection) REFERENCES intersections(intersection_id),
    CONSTRAINT fk_seg_to   FOREIGN KEY (to_intersection)   REFERENCES intersections(intersection_id)
) ENGINE=InnoDB;

CREATE TABLE traffic_signals (
    signal_id         INT AUTO_INCREMENT PRIMARY KEY,
    intersection_id   INT          NOT NULL UNIQUE,          -- 1:1 with intersection
    controller_model  VARCHAR(80),
    mode              VARCHAR(20)  NOT NULL DEFAULT 'fixed',
    status            VARCHAR(20)  NOT NULL DEFAULT 'online',
    installed_on      DATE,
    CONSTRAINT chk_sig_mode   CHECK (mode   IN ('fixed','adaptive','flash','manual','off')),
    CONSTRAINT chk_sig_status CHECK (status IN ('online','offline','fault')),
    CONSTRAINT fk_sig_int FOREIGN KEY (intersection_id) REFERENCES intersections(intersection_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE sensors (
    sensor_id     INT AUTO_INCREMENT PRIMARY KEY,
    segment_id    INT          NOT NULL,
    sensor_type   VARCHAR(20)  NOT NULL,
    latitude      DECIMAL(9,6) NOT NULL,
    longitude     DECIMAL(9,6) NOT NULL,
    status        VARCHAR(20)  NOT NULL DEFAULT 'active',
    installed_on  DATE,
    last_seen_at  DATETIME,
    CONSTRAINT chk_sen_type   CHECK (sensor_type IN ('loop','camera','radar','lidar','bluetooth','anpr')),
    CONSTRAINT chk_sen_status CHECK (status IN ('active','inactive','faulty')),
    CONSTRAINT fk_sen_seg FOREIGN KEY (segment_id) REFERENCES road_segments(segment_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- NOTE: segment_id and congestion level are NOT stored here (they are derivable:
-- sensor_id -> segment_id, occupancy -> level). Removing them is the 3NF step.
CREATE TABLE traffic_readings (
    reading_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
    sensor_id      INT          NOT NULL,
    recorded_at    DATETIME     NOT NULL,
    vehicle_count  INT          NOT NULL,
    avg_speed_kmh  DECIMAL(5,1) NOT NULL,
    occupancy_pct  DECIMAL(5,2) NOT NULL,
    CONSTRAINT uq_reading UNIQUE (sensor_id, recorded_at),
    CONSTRAINT chk_rd_count CHECK (vehicle_count >= 0),
    CONSTRAINT chk_rd_speed CHECK (avg_speed_kmh >= 0),
    CONSTRAINT chk_rd_occ   CHECK (occupancy_pct BETWEEN 0 AND 100),
    CONSTRAINT fk_rd_sensor FOREIGN KEY (sensor_id) REFERENCES sensors(sensor_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    INDEX idx_rd_time (recorded_at)
) ENGINE=InnoDB;

CREATE TABLE vehicles (
    vehicle_id    INT AUTO_INCREMENT PRIMARY KEY,
    plate_number  VARCHAR(20) NOT NULL UNIQUE,
    vehicle_type  VARCHAR(20) NOT NULL,
    make          VARCHAR(60),
    model         VARCHAR(60),
    owner_name    VARCHAR(120),
    is_fleet      BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT chk_veh_type CHECK (vehicle_type IN ('car','motorcycle','bus','truck','emergency','other'))
) ENGINE=InnoDB;

-- 3NF decomposition: violation_type -> base_fine was split out of VIOLATIONS
CREATE TABLE violation_types (
    type_id      INT AUTO_INCREMENT PRIMARY KEY,
    type_name    VARCHAR(30)   NOT NULL UNIQUE,
    base_fine    DECIMAL(10,2) NOT NULL,
    description  VARCHAR(255),
    CONSTRAINT chk_vt_fine CHECK (base_fine >= 0)
) ENGINE=InnoDB;

CREATE TABLE violations (
    violation_id    INT AUTO_INCREMENT PRIMARY KEY,
    vehicle_id      INT          NOT NULL,
    sensor_id       INT,
    type_id         INT          NOT NULL,
    recorded_speed  DECIMAL(5,1),
    status          VARCHAR(20)  NOT NULL DEFAULT 'pending',
    occurred_at     DATETIME     NOT NULL,
    CONSTRAINT chk_vio_status CHECK (status IN ('pending','issued','paid','disputed','dismissed')),
    CONSTRAINT fk_vio_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_vio_sensor  FOREIGN KEY (sensor_id)  REFERENCES sensors(sensor_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_vio_type    FOREIGN KEY (type_id)    REFERENCES violation_types(type_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE incidents (
    incident_id    INT AUTO_INCREMENT PRIMARY KEY,
    segment_id     INT,
    incident_type  VARCHAR(30) NOT NULL,
    severity       TINYINT     NOT NULL,
    latitude       DECIMAL(9,6),
    longitude      DECIMAL(9,6),
    description    TEXT,
    status         VARCHAR(20) NOT NULL DEFAULT 'reported',
    reported_by    INT,
    reported_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cleared_at     DATETIME,
    CONSTRAINT chk_inc_type   CHECK (incident_type IN ('accident','breakdown','roadwork','weather','event','obstruction')),
    CONSTRAINT chk_inc_sev    CHECK (severity BETWEEN 1 AND 5),
    CONSTRAINT chk_inc_status CHECK (status IN ('reported','verified','responding','cleared')),
    CONSTRAINT chk_inc_time   CHECK (cleared_at IS NULL OR cleared_at >= reported_at),
    CONSTRAINT fk_inc_seg  FOREIGN KEY (segment_id)  REFERENCES road_segments(segment_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_inc_user FOREIGN KEY (reported_by) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    INDEX idx_inc_status (status, reported_at)
) ENGINE=InnoDB;

CREATE TABLE alerts (
    alert_id     INT AUTO_INCREMENT PRIMARY KEY,
    incident_id  INT,
    segment_id   INT,
    alert_type   VARCHAR(30)  NOT NULL,
    message      TEXT         NOT NULL,
    channel      VARCHAR(20)  NOT NULL DEFAULT 'dashboard',
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at   DATETIME,
    CONSTRAINT chk_alt_channel CHECK (channel IN ('dashboard','vms','sms','app','email')),
    CONSTRAINT fk_alt_inc FOREIGN KEY (incident_id) REFERENCES incidents(incident_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_alt_seg FOREIGN KEY (segment_id)  REFERENCES road_segments(segment_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- A work order targets exactly ONE asset (signal OR sensor OR road segment).
-- Three real foreign keys replace the old (asset_type, asset_id) pair, which
-- could not be enforced by the database.
CREATE TABLE work_orders (
    work_order_id  INT AUTO_INCREMENT PRIMARY KEY,
    signal_id      INT,
    sensor_id      INT,
    segment_id     INT,
    assigned_to    INT,
    priority       TINYINT     NOT NULL DEFAULT 3,
    description    TEXT,
    status         VARCHAR(20) NOT NULL DEFAULT 'open',
    created_at     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at   DATETIME,
    CONSTRAINT chk_wo_priority CHECK (priority BETWEEN 1 AND 5),
    CONSTRAINT chk_wo_status   CHECK (status IN ('open','in_progress','done','cancelled')),
    CONSTRAINT chk_wo_one_asset CHECK
        ((signal_id IS NOT NULL) + (sensor_id IS NOT NULL) + (segment_id IS NOT NULL) = 1),
    CONSTRAINT fk_wo_signal  FOREIGN KEY (signal_id)  REFERENCES traffic_signals(signal_id),
    CONSTRAINT fk_wo_sensor  FOREIGN KEY (sensor_id)  REFERENCES sensors(sensor_id),
    CONSTRAINT fk_wo_segment FOREIGN KEY (segment_id) REFERENCES road_segments(segment_id),
    CONSTRAINT fk_wo_user    FOREIGN KEY (assigned_to) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

SHOW TABLES;

-- ---------------------------------------------------------------------
-- 8.7  ADVANCED FEATURES (created before data so triggers fire on inserts)
--      3 triggers + 4 views
-- ---------------------------------------------------------------------
DELIMITER $$

-- TRIGGER 1: every new reading refreshes the sensor's heartbeat.
CREATE TRIGGER trg_reading_heartbeat
AFTER INSERT ON traffic_readings
FOR EACH ROW
BEGIN
    UPDATE sensors
       SET last_seen_at = NEW.recorded_at
     WHERE sensor_id = NEW.sensor_id
       AND (last_seen_at IS NULL OR last_seen_at < NEW.recorded_at);
END$$

-- TRIGGER 2: stamp cleared_at automatically when an incident is cleared.
CREATE TRIGGER trg_incident_cleared
BEFORE UPDATE ON incidents
FOR EACH ROW
BEGIN
    IF NEW.status = 'cleared' AND OLD.status <> 'cleared' AND NEW.cleared_at IS NULL THEN
        SET NEW.cleared_at = NOW();
    END IF;
END$$

-- TRIGGER 3: a severe incident (>=4) automatically raises a dashboard alert.
CREATE TRIGGER trg_incident_alert
AFTER INSERT ON incidents
FOR EACH ROW
BEGIN
    IF NEW.severity >= 4 THEN
        INSERT INTO alerts (incident_id, segment_id, alert_type, message, channel, expires_at)
        VALUES (NEW.incident_id, NEW.segment_id, 'severe_incident',
                CONCAT('Severe ', NEW.incident_type, ' reported (severity ', NEW.severity, ')'),
                'dashboard', DATE_ADD(NOW(), INTERVAL 6 HOUR));
    END IF;
END$$

DELIMITER ;

-- VIEW 1: incidents that are not yet cleared, with the road name
CREATE VIEW v_active_incidents AS
SELECT i.incident_id, s.name AS segment_name, i.incident_type, i.severity,
       i.status, i.reported_at
FROM incidents i
LEFT JOIN road_segments s ON s.segment_id = i.segment_id
WHERE i.status <> 'cleared';

-- VIEW 2: latest reading of every sensor with a derived congestion level (0-5)
CREATE VIEW v_latest_readings AS
SELECT r.sensor_id, s.segment_id, r.recorded_at, r.vehicle_count,
       r.avg_speed_kmh, r.occupancy_pct,
       CASE WHEN r.occupancy_pct < 20 THEN 0
            WHEN r.occupancy_pct < 40 THEN 1
            WHEN r.occupancy_pct < 60 THEN 2
            WHEN r.occupancy_pct < 75 THEN 3
            WHEN r.occupancy_pct < 90 THEN 4
            ELSE 5 END AS congestion_lvl
FROM traffic_readings r
JOIN sensors s ON s.sensor_id = r.sensor_id
WHERE r.recorded_at = (SELECT MAX(r2.recorded_at)
                       FROM traffic_readings r2
                       WHERE r2.sensor_id = r.sensor_id);

-- VIEW 3: signal + intersection details for the control room
CREATE VIEW v_signal_overview AS
SELECT sg.signal_id, i.name AS intersection_name, sg.controller_model,
       sg.mode, sg.status, i.latitude, i.longitude
FROM traffic_signals sg
JOIN intersections i ON i.intersection_id = sg.intersection_id;

-- VIEW 4: revenue / pending fines per violation type
CREATE VIEW v_fine_summary AS
SELECT t.type_name, COUNT(*) AS total_violations,
       SUM(t.base_fine) AS total_fine,
       SUM(CASE WHEN v.status = 'paid' THEN t.base_fine ELSE 0 END) AS collected
FROM violations v
JOIN violation_types t ON t.type_id = v.type_id
GROUP BY t.type_name;

-- ---------------------------------------------------------------------
-- 8.3  DATA INSERTION
-- ---------------------------------------------------------------------
INSERT INTO roles (name, description) VALUES
 ('admin',    'Full system access'),
 ('operator', 'Control room operator'),
 ('viewer',   'Read-only access');

INSERT INTO users (role_id, full_name, email, password_hash) VALUES
 (1, 'Anita Verma',   'anita.verma@ttms.in',   'hash_demo_1'),
 (2, 'Rohit Sharma',  'rohit.sharma@ttms.in',  'hash_demo_2'),
 (2, 'Meena Joshi',   'meena.joshi@ttms.in',   'hash_demo_3'),
 (2, 'Imran Khan',    'imran.khan@ttms.in',    'hash_demo_4'),
 (3, 'Suresh Patel',  'suresh.patel@ttms.in',  'hash_demo_5');

INSERT INTO intersections (name, latitude, longitude) VALUES
 ('Board Office Chauraha',   23.231000, 77.426000),
 ('Roshanpura Square',       23.236000, 77.409000),
 ('New Market Square',       23.233000, 77.399000),
 ('Habibganj Naka',          23.229000, 77.438000),
 ('Vallabh Bhawan Junction', 23.242000, 77.413000),
 ('Hamidia Road Junction',   23.259000, 77.401000),
 ('Bittan Market Square',    23.220000, 77.433000),
 ('Kolar Road Junction',     23.190000, 77.423000);

INSERT INTO road_segments (name, road_class, from_intersection, to_intersection, length_m, lanes, speed_limit_kmh, is_one_way, status) VALUES
 ('MP Nagar Main Road',     'arterial',  1, 2, 1500, 3, 50, FALSE, 'open'),
 ('Link Road No. 1',        'arterial',  2, 3, 1100, 3, 50, FALSE, 'open'),
 ('Roshanpura-Vallabh Link','collector', 2, 5, 1400, 2, 40, FALSE, 'open'),
 ('Hamidia Road',           'arterial',  3, 6, 3200, 3, 50, FALSE, 'restricted'),
 ('Habibganj Road',         'arterial',  1, 4, 2100, 3, 50, FALSE, 'open'),
 ('Bittan Market Road',     'collector', 4, 7, 1900, 2, 40, TRUE,  'open'),
 ('Hoshangabad Road',       'highway',   7, 8, 4200, 4, 80, FALSE, 'open'),
 ('Kolar Link Road',        'collector', 4, 8, 5000, 2, 40, FALSE, 'open'),
 ('Shivaji Nagar Road',     'local',     5, 1, 1300, 2, 30, FALSE, 'open'),
 ('Station Approach Road',  'local',     6, 3, 1000, 2, 30, TRUE,  'closed');

INSERT INTO traffic_signals (intersection_id, controller_model, mode, status, installed_on) VALUES
 (1, 'ATC-2070', 'adaptive', 'online',  '2024-03-15'),
 (2, 'ATC-2070', 'fixed',    'online',  '2023-11-02'),
 (3, 'ATC-2070', 'adaptive', 'online',  '2024-01-20'),
 (4, 'Siemens-S9','fixed',   'fault',   '2022-08-10'),
 (5, 'Siemens-S9','manual',  'online',  '2022-09-05'),
 (6, 'ATC-2070', 'fixed',    'offline', '2023-05-18');

INSERT INTO sensors (segment_id, sensor_type, latitude, longitude, status, installed_on) VALUES
 (1, 'radar',  23.233500, 77.417500, 'active',   '2024-02-01'),
 (2, 'camera', 23.234500, 77.404000, 'active',   '2024-02-01'),
 (3, 'loop',   23.239000, 77.411000, 'active',   '2023-12-12'),
 (4, 'camera', 23.246000, 77.400500, 'active',   '2024-04-04'),
 (5, 'radar',  23.230000, 77.432000, 'active',   '2024-02-20'),
 (6, 'anpr',   23.224500, 77.435500, 'active',   '2024-05-09'),
 (7, 'lidar',  23.205000, 77.428000, 'active',   '2024-06-01'),
 (8, 'loop',   23.209500, 77.430500, 'faulty',   '2023-10-30'),
 (1, 'camera', 23.232000, 77.421000, 'active',   '2024-07-07'),
 (5, 'anpr',   23.229500, 77.434500, 'inactive', '2024-07-07');

-- readings (inserting fires trg_reading_heartbeat, which sets sensors.last_seen_at)
INSERT INTO traffic_readings (sensor_id, recorded_at, vehicle_count, avg_speed_kmh, occupancy_pct) VALUES
 (1, '2026-10-09 08:00:00', 272, 17.6, 70.42),
 (1, '2026-10-09 09:00:00', 185, 34.2, 43.43),
 (1, '2026-10-09 10:00:00', 206, 26.6, 51.46),
 (1, '2026-10-09 18:00:00', 259, 22.1, 63.11),
 (2, '2026-10-09 08:00:00', 305, 18.0, 71.82),
 (2, '2026-10-09 09:00:00', 223, 26.6, 53.24),
 (2, '2026-10-09 10:00:00', 248, 23.9, 56.41),
 (2, '2026-10-09 18:00:00', 299, 15.2, 79.88),
 (3, '2026-10-09 08:00:00', 181, 23.1, 49.24),
 (3, '2026-10-09 09:00:00', 104, 35.0, 24.91),
 (3, '2026-10-09 10:00:00', 138, 31.2, 33.44),
 (3, '2026-10-09 18:00:00', 205, 23.3, 49.43),
 (4, '2026-10-09 08:00:00', 408, 11.6, 91.45),
 (4, '2026-10-09 09:00:00', 220, 26.3, 60.43),
 (4, '2026-10-09 10:00:00', 206, 25.7, 56.23),
 (4, '2026-10-09 18:00:00', 326, 11.8, 84.29),
 (5, '2026-10-09 08:00:00', 254, 22.5, 64.13),
 (5, '2026-10-09 09:00:00', 176, 33.4, 39.01),
 (5, '2026-10-09 10:00:00', 166, 33.0, 44.28),
 (5, '2026-10-09 18:00:00', 259, 20.8, 65.25),
 (6, '2026-10-09 08:00:00', 180, 27.1, 43.37),
 (6, '2026-10-09 09:00:00', 121, 34.0, 27.72),
 (6, '2026-10-09 10:00:00', 87, 31.1, 22.25),
 (6, '2026-10-09 18:00:00', 157, 27.6, 34.71),
 (7, '2026-10-09 08:00:00', 243, 56.9, 35.77),
 (7, '2026-10-09 09:00:00', 129, 71.9, 20.0),
 (7, '2026-10-09 10:00:00', 122, 69.1, 18.43),
 (7, '2026-10-09 18:00:00', 204, 63.9, 28.4),
 (9, '2026-10-09 08:00:00', 270, 24.1, 58.79),
 (9, '2026-10-09 09:00:00', 149, 31.5, 40.91),
 (9, '2026-10-09 10:00:00', 158, 36.8, 36.12),
 (9, '2026-10-09 18:00:00', 235, 23.0, 59.07),
 (8, '2026-10-09 08:00:00', 92, 31.5, 38.0);

INSERT INTO vehicles (plate_number, vehicle_type, make, model, owner_name, is_fleet) VALUES
 ('MP04AB1234', 'car',        'Maruti',  'Swift',    'Rahul Mehta',      FALSE),
 ('MP04CD5678', 'motorcycle', 'Honda',   'Activa',   'Neha Singh',       FALSE),
 ('MP09EF9012', 'bus',        'Tata',    'Starbus',  'BCLL Bhopal',      TRUE),
 ('MP04GH3456', 'truck',      'Ashok Leyland','Dost','Sharma Logistics', TRUE),
 ('MP04IJ7890', 'car',        'Hyundai', 'Creta',    'Vikram Rao',       FALSE),
 ('MP04KL1122', 'emergency',  'Force',   'Traveller','District Hospital',TRUE),
 ('MP20MN3344', 'car',        'Tata',    'Nexon',    'Pooja Dubey',      FALSE),
 ('MP04OP5566', 'motorcycle', 'Bajaj',   'Pulsar',   'Arjun Tiwari',     FALSE),
 ('MP04QR7788', 'truck',      'Eicher',  'Pro 2049', 'Gupta Transport',  TRUE),
 ('MP04ST9900', 'car',        'Honda',   'City',     'Kavita Nair',      FALSE);

INSERT INTO violation_types (type_name, base_fine, description) VALUES
 ('speeding',        1000.00, 'Exceeded posted speed limit'),
 ('red_light',       5000.00, 'Crossed stop line on red signal'),
 ('illegal_parking',  500.00, 'Parked in a no-parking zone'),
 ('wrong_way',       2000.00, 'Drove against one-way traffic');

INSERT INTO violations (vehicle_id, sensor_id, type_id, recorded_speed, status, occurred_at) VALUES
 (1, 1, 1, 68.0, 'issued',    '2026-10-08 09:15:00'),
 (2, 5, 1, 72.5, 'paid',      '2026-10-08 10:40:00'),
 (5, 2, 2, NULL, 'pending',   '2026-10-08 18:05:00'),
 (7, 4, 2, NULL, 'issued',    '2026-10-09 08:20:00'),
 (8, 6, 4, NULL, 'paid',      '2026-10-09 09:10:00'),
 (4, 7, 1, 96.0, 'disputed',  '2026-10-09 11:30:00'),
 (10,9, 1, 64.0, 'pending',   '2026-10-09 12:45:00'),
 (1, 2, 3, NULL, 'paid',      '2026-10-07 17:00:00'),
 (9, 7, 1, 101.5,'issued',    '2026-10-09 14:20:00'),
 (2, 6, 4, NULL, 'dismissed', '2026-10-06 19:30:00'),
 (7, 1, 1, 66.0, 'paid',      '2026-10-05 08:50:00');

INSERT INTO incidents (segment_id, incident_type, severity, latitude, longitude, description, status, reported_by, reported_at, cleared_at) VALUES
 (4, 'roadwork',    2, 23.246000, 77.400500, 'Lane closure for resurfacing',          'verified',   2, '2026-10-08 07:30:00', NULL),
 (1, 'accident',    4, 23.233500, 77.417500, 'Two-vehicle collision near MP Nagar',   'responding', 3, '2026-10-09 08:25:00', NULL),
 (2, 'breakdown',   2, 23.234500, 77.404000, 'Bus broke down in left lane',           'cleared',    2, '2026-10-08 12:10:00', '2026-10-08 13:05:00'),
 (7, 'weather',     3, NULL,      NULL,      'Heavy rain, reduced visibility',        'verified',   4, '2026-10-09 15:00:00', NULL),
 (5, 'event',       2, 23.230000, 77.432000, 'Procession causing slow traffic',       'reported',   3, '2026-10-10 09:00:00', NULL),
 (6, 'obstruction', 3, 23.224500, 77.435500, 'Fallen tree on carriageway',            'responding', 4, '2026-10-10 07:45:00', NULL),
 (10,'roadwork',    1, NULL,      NULL,      'Station approach closed for drainage',  'verified',   1, '2026-10-01 10:00:00', NULL),
 (3, 'accident',    5, 23.239000, 77.411000, 'Truck overturned, road blocked',       'reported',   2, '2026-10-10 10:15:00', NULL);

INSERT INTO alerts (incident_id, segment_id, alert_type, message, channel, expires_at) VALUES
 (NULL, 4, 'congestion', 'Heavy congestion on Hamidia Road', 'dashboard', '2026-10-10 20:00:00'),
 (NULL, 7, 'weather',    'Rain advisory on Hoshangabad Road', 'sms',      '2026-10-10 18:00:00');

INSERT INTO work_orders (signal_id, sensor_id, segment_id, assigned_to, priority, description, status, created_at) VALUES
 (4,    NULL, NULL, 2, 1, 'Repair faulty signal controller at Habibganj Naka', 'in_progress', '2026-10-09 09:00:00'),
 (6,    NULL, NULL, 3, 2, 'Restore power to Hamidia Road signal',               'open',        '2026-10-09 11:00:00'),
 (NULL, 8,    NULL, 4, 3, 'Replace faulty loop detector',                       'open',        '2026-10-08 14:00:00'),
 (NULL, NULL, 4,    2, 2, 'Resurface Hamidia Road lane',                        'in_progress', '2026-10-08 08:00:00'),
 (NULL, 10,   NULL, 4, 4, 'Reactivate ANPR camera on Habibganj Road',           'done',        '2026-10-02 10:00:00');

-- ---------------------------------------------------------------------
-- 8.5  SAMPLE DATABASE CONTENTS   (screenshot each result grid)
-- ---------------------------------------------------------------------
SELECT * FROM roles;
SELECT user_id, role_id, full_name, email FROM users;
SELECT * FROM intersections;
SELECT * FROM road_segments;
SELECT * FROM traffic_signals;
SELECT * FROM sensors;
SELECT * FROM traffic_readings LIMIT 10;
SELECT * FROM vehicles;
SELECT * FROM violation_types;
SELECT * FROM violations;
SELECT * FROM incidents;
SELECT * FROM alerts;      -- note the alert auto-created by trg_incident_alert
SELECT * FROM work_orders;
SELECT 'roles' AS tbl, COUNT(*) AS row_count FROM roles
UNION ALL SELECT 'users', COUNT(*) FROM users
UNION ALL SELECT 'intersections', COUNT(*) FROM intersections
UNION ALL SELECT 'road_segments', COUNT(*) FROM road_segments
UNION ALL SELECT 'traffic_signals', COUNT(*) FROM traffic_signals
UNION ALL SELECT 'sensors', COUNT(*) FROM sensors
UNION ALL SELECT 'traffic_readings', COUNT(*) FROM traffic_readings
UNION ALL SELECT 'vehicles', COUNT(*) FROM vehicles
UNION ALL SELECT 'violation_types', COUNT(*) FROM violation_types
UNION ALL SELECT 'violations', COUNT(*) FROM violations
UNION ALL SELECT 'incidents', COUNT(*) FROM incidents
UNION ALL SELECT 'alerts', COUNT(*) FROM alerts
UNION ALL SELECT 'work_orders', COUNT(*) FROM work_orders;

-- ---------------------------------------------------------------------
-- 8.4  DATA MODIFICATION AND DELETION
-- ---------------------------------------------------------------------
-- UPDATE 1: put a signal into adaptive mode
UPDATE traffic_signals SET mode = 'adaptive' WHERE signal_id = 2;
SELECT signal_id, mode FROM traffic_signals WHERE signal_id = 2;

-- UPDATE 2: clear an incident -> trigger trg_incident_cleared stamps cleared_at
UPDATE incidents SET status = 'cleared' WHERE incident_id = 6;
SELECT incident_id, status, reported_at, cleared_at FROM incidents WHERE incident_id = 6;

-- UPDATE 3: restore the closed road
UPDATE road_segments SET status = 'open' WHERE segment_id = 10;

-- DELETE 1: remove an expired alert
DELETE FROM alerts WHERE alert_type = 'weather';

-- DELETE 2 (ON DELETE CASCADE demo, rolled back so data is kept):
START TRANSACTION;
SELECT COUNT(*) AS readings_before FROM traffic_readings WHERE sensor_id = 1;
DELETE FROM sensors WHERE sensor_id = 1;
SELECT COUNT(*) AS readings_after  FROM traffic_readings WHERE sensor_id = 1;  -- 0 : cascaded
ROLLBACK;
SELECT COUNT(*) AS readings_restored FROM traffic_readings WHERE sensor_id = 1;

-- ---------------------------------------------------------------------
-- 8.6  SQL QUERY IMPLEMENTATION
-- ---------------------------------------------------------------------
-- Q1  Simple SELECT with condition: roads that are not fully open
SELECT segment_id, name, road_class, status FROM road_segments WHERE status <> 'open';

-- Q2  ORDER BY: incidents, most severe first
SELECT incident_id, incident_type, severity, status
FROM incidents ORDER BY severity DESC, reported_at DESC;

-- Q3  Aggregate functions: network-wide statistics from readings
SELECT COUNT(*) AS readings, SUM(vehicle_count) AS total_vehicles,
       ROUND(AVG(avg_speed_kmh),1) AS avg_speed,
       MIN(avg_speed_kmh) AS slowest, MAX(occupancy_pct) AS peak_occupancy
FROM traffic_readings;

-- Q4  GROUP BY + HAVING: segments whose average speed is below 25 km/h (heavily congested)
SELECT s.name, ROUND(AVG(r.avg_speed_kmh),1) AS avg_speed, COUNT(*) AS samples
FROM traffic_readings r
JOIN sensors n      ON n.sensor_id  = r.sensor_id
JOIN road_segments s ON s.segment_id = n.segment_id
GROUP BY s.segment_id, s.name
HAVING AVG(r.avg_speed_kmh) < 25
ORDER BY avg_speed;

-- Q5  INNER JOIN: signals with their intersection names
SELECT sg.signal_id, i.name AS intersection, sg.mode, sg.status
FROM traffic_signals sg
INNER JOIN intersections i ON i.intersection_id = sg.intersection_id;

-- Q6  LEFT JOIN: intersections that have NO signal installed
SELECT i.intersection_id, i.name
FROM intersections i
LEFT JOIN traffic_signals sg ON sg.intersection_id = i.intersection_id
WHERE sg.signal_id IS NULL;

-- Q7  RIGHT JOIN: every segment with its number of sensors (0 if none)
SELECT s.name, COUNT(n.sensor_id) AS sensors
FROM sensors n
RIGHT JOIN road_segments s ON s.segment_id = n.segment_id
GROUP BY s.segment_id, s.name
ORDER BY sensors DESC;

-- Q8  SELF JOIN: pairs of roads that meet at the same intersection
SELECT a.name AS road_1, b.name AS road_2, i.name AS meeting_point
FROM road_segments a
JOIN road_segments b ON a.to_intersection = b.from_intersection AND a.segment_id <> b.segment_id
JOIN intersections i ON i.intersection_id = a.to_intersection;

-- Q9  Subquery: vehicles that own a violation of the most expensive type
SELECT plate_number, owner_name FROM vehicles
WHERE vehicle_id IN (SELECT v.vehicle_id FROM violations v
                     WHERE v.type_id = (SELECT type_id FROM violation_types
                                        ORDER BY base_fine DESC LIMIT 1));

-- Q10 IN: segments that currently have an uncleared incident
SELECT name FROM road_segments
WHERE segment_id IN (SELECT segment_id FROM incidents WHERE status <> 'cleared');

-- Q11 EXISTS: vehicles with at least one unpaid (pending/issued) violation
SELECT v.plate_number, v.owner_name FROM vehicles v
WHERE EXISTS (SELECT 1 FROM violations x
              WHERE x.vehicle_id = v.vehicle_id AND x.status IN ('pending','issued'));

-- Q12 ALL: segments whose speed limit is higher than EVERY collector road
SELECT name, speed_limit_kmh FROM road_segments
WHERE speed_limit_kmh > ALL (SELECT speed_limit_kmh FROM road_segments WHERE road_class = 'collector');

-- Q13 ANY: segments with a limit above ANY local road
SELECT name, road_class, speed_limit_kmh FROM road_segments
WHERE speed_limit_kmh > ANY (SELECT speed_limit_kmh FROM road_segments WHERE road_class = 'local');

-- Q14 Multi-table (5 tables): every speeding fine with vehicle, road and fine amount
SELECT v.plate_number, t.type_name, t.base_fine, vi.recorded_speed,
       s.name AS road, s.speed_limit_kmh
FROM violations vi
JOIN vehicles v        ON v.vehicle_id  = vi.vehicle_id
JOIN violation_types t ON t.type_id     = vi.type_id
JOIN sensors n         ON n.sensor_id   = vi.sensor_id
JOIN road_segments s   ON s.segment_id  = n.segment_id
WHERE t.type_name = 'speeding'
ORDER BY vi.recorded_speed DESC;

-- Q15 Business: top 3 most congested roads (average occupancy)
SELECT s.name, ROUND(AVG(r.occupancy_pct),1) AS avg_occupancy
FROM traffic_readings r
JOIN sensors n ON n.sensor_id = r.sensor_id
JOIN road_segments s ON s.segment_id = n.segment_id
GROUP BY s.segment_id, s.name
ORDER BY avg_occupancy DESC LIMIT 3;

-- Q16 Business: average time taken to clear incidents (minutes)
SELECT incident_type, ROUND(AVG(TIMESTAMPDIFF(MINUTE, reported_at, cleared_at)),0) AS avg_minutes
FROM incidents WHERE cleared_at IS NOT NULL GROUP BY incident_type;

-- Q17 Business: speeding vehicles driving more than 20 km/h over the limit
SELECT v.plate_number, vi.recorded_speed, s.speed_limit_kmh,
       (vi.recorded_speed - s.speed_limit_kmh) AS over_by
FROM violations vi
JOIN vehicles v      ON v.vehicle_id = vi.vehicle_id
JOIN sensors n       ON n.sensor_id  = vi.sensor_id
JOIN road_segments s ON s.segment_id = n.segment_id
WHERE vi.recorded_speed - s.speed_limit_kmh > 20;

-- Q18 Business: assets needing maintenance (open work orders, high priority first)
SELECT w.work_order_id, w.priority, w.status, w.description, u.full_name AS assigned_to
FROM work_orders w LEFT JOIN users u ON u.user_id = w.assigned_to
WHERE w.status IN ('open','in_progress') ORDER BY w.priority;

-- Q19 Views in use
SELECT * FROM v_active_incidents;
SELECT * FROM v_latest_readings ORDER BY congestion_lvl DESC;
SELECT * FROM v_signal_overview;
SELECT * FROM v_fine_summary;

-- Q20 Trigger demo: a severity-5 incident automatically creates an alert
INSERT INTO incidents (segment_id, incident_type, severity, description, reported_by)
VALUES (2, 'accident', 5, 'Demo: major pile-up', 2);
SELECT alert_id, incident_id, alert_type, message, channel FROM alerts ORDER BY alert_id DESC LIMIT 1;

-- Q21 Trigger demo: a new reading refreshes the sensor heartbeat
INSERT INTO traffic_readings (sensor_id, recorded_at, vehicle_count, avg_speed_kmh, occupancy_pct)
VALUES (3, '2026-10-10 11:00:00', 120, 33.5, 45.00);
SELECT sensor_id, last_seen_at FROM sensors WHERE sensor_id = 3;

-- ---------------------------------------------------------------------
-- 10.3  CONSTRAINT TESTING  (each statement below SHOULD FAIL with an error;
--       screenshot the error message in Workbench's "Output" panel)
-- ---------------------------------------------------------------------
-- T2  Duplicate key (UNIQUE plate_number)
INSERT INTO vehicles (plate_number, vehicle_type) VALUES ('MP04AB1234', 'car');
-- T3  Invalid foreign key (segment 999 does not exist)
INSERT INTO sensors (segment_id, sensor_type, latitude, longitude) VALUES (999, 'radar', 23.2, 77.4);
-- T4  Negative stock-like value (negative vehicle count) -> CHECK
INSERT INTO traffic_readings (sensor_id, recorded_at, vehicle_count, avg_speed_kmh, occupancy_pct)
VALUES (2, '2026-10-10 12:00:00', -5, 40.0, 30.0);
-- T5  Invalid severity -> CHECK
INSERT INTO incidents (segment_id, incident_type, severity) VALUES (1, 'accident', 9);
-- T6  Work order pointing at two assets -> CHECK
INSERT INTO work_orders (signal_id, sensor_id, description) VALUES (1, 1, 'invalid: two assets');
-- T7  Second signal on the same intersection -> UNIQUE (1:1)
INSERT INTO traffic_signals (intersection_id, mode) VALUES (1, 'fixed');
-- T8  Deleting a vehicle that has violations -> ON DELETE RESTRICT
DELETE FROM vehicles WHERE vehicle_id = 1;
-- T9  Segment starting and ending at the same intersection -> CHECK
INSERT INTO road_segments (name, road_class, from_intersection, to_intersection, length_m, speed_limit_kmh)
VALUES ('Loop road', 'local', 1, 1, 500, 30);
