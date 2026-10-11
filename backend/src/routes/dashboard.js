const express = require('express');
const router = express.Router();
const db = require('../db');

function hoursParam(value, fallback = 12) {
  const n = Number(value);
  return [6, 12, 24, 48, 72].includes(n) ? n : fallback;
}

router.get('/summary', async (req, res) => {
  try {
    const [incidents, speed, sensors, signals] = await Promise.all([
      db.query(`SELECT COUNT(*) AS n FROM incidents WHERE status <> 'cleared'`),
      db.query(`SELECT ROUND(AVG(avg_speed_kmh), 1) AS avg_speed FROM v_latest_readings`),
      db.query(`SELECT SUM(status='active') AS active, COUNT(*) AS total FROM sensors`),
      db.query(`SELECT SUM(mode='adaptive') AS adaptive, COUNT(*) AS total FROM traffic_signals`),
    ]);
    res.json({
      active_incidents: Number(incidents[0]?.n || 0),
      avg_network_speed: speed[0]?.avg_speed == null ? null : Number(speed[0].avg_speed),
      sensors_active: Number(sensors[0]?.active || 0),
      sensors_total: Number(sensors[0]?.total || 0),
      adaptive_signals: Number(signals[0]?.adaptive || 0),
      signals_total: Number(signals[0]?.total || 0),
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load dashboard summary' });
  }
});

router.get('/corridors', async (req, res) => {
  try {
    const rows = await db.query(`
      SELECT s.segment_id, s.name, s.road_class, s.lanes, s.status,
             s.speed_limit_kmh, s.length_m,
             lr.latest_speed, COALESCE(lr.vehicles_per_hr, 0) AS vehicles_per_hr,
             lr.occupancy_pct, COALESCE(ic.active_incidents, 0) AS active_incidents
      FROM road_segments s
      LEFT JOIN (
        SELECT segment_id,
               ROUND(AVG(avg_speed_kmh), 1) AS latest_speed,
               SUM(vehicle_count) AS vehicles_per_hr,
               ROUND(AVG(occupancy_pct), 1) AS occupancy_pct
        FROM v_latest_readings
        GROUP BY segment_id
      ) lr ON lr.segment_id = s.segment_id
      LEFT JOIN (
        SELECT segment_id, COUNT(*) AS active_incidents
        FROM incidents
        WHERE status <> 'cleared' AND segment_id IS NOT NULL
        GROUP BY segment_id
      ) ic ON ic.segment_id = s.segment_id
      ORDER BY s.segment_id`);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load corridor details' });
  }
});

router.get('/trends', async (req, res) => {
  const hours = hoursParam(req.query.hours, 12);
  try {
    const rows = await db.query(`
      SELECT s.segment_id, s.name,
             DATE_FORMAT(r.recorded_at, '%Y-%m-%d %H:00:00') AS bucket,
             ROUND(AVG(r.avg_speed_kmh), 1) AS avg_speed,
             SUM(r.vehicle_count) AS vehicle_count,
             ROUND(AVG(r.occupancy_pct), 1) AS occupancy_pct
      FROM traffic_readings r
      JOIN sensors se ON se.sensor_id = r.sensor_id
      JOIN road_segments s ON s.segment_id = se.segment_id
      WHERE r.recorded_at >= DATE_SUB(
        (SELECT MAX(recorded_at) FROM traffic_readings), INTERVAL ${hours} HOUR
      )
      GROUP BY s.segment_id, s.name, bucket
      ORDER BY bucket, s.segment_id`);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load trends' });
  }
});

router.get('/hourly-volume', async (req, res) => {
  const hours = hoursParam(req.query.hours, 24);
  try {
    const rows = await db.query(`
      SELECT DATE_FORMAT(recorded_at, '%Y-%m-%d %H:00:00') AS bucket,
             SUM(vehicle_count) AS vehicle_count
      FROM traffic_readings
      WHERE recorded_at >= DATE_SUB(
        (SELECT MAX(recorded_at) FROM traffic_readings), INTERVAL ${hours} HOUR
      )
      GROUP BY bucket
      ORDER BY bucket`);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load hourly volume' });
  }
});

router.get('/watchlist', async (req, res) => {
  try {
    const rows = await db.query(`
      SELECT s.segment_id, s.name, s.status, s.speed_limit_kmh,
             lr.latest_speed, COALESCE(ic.active_incidents, 0) AS active_incidents
      FROM road_segments s
      LEFT JOIN (
        SELECT segment_id, ROUND(AVG(avg_speed_kmh), 1) AS latest_speed
        FROM v_latest_readings
        GROUP BY segment_id
      ) lr ON lr.segment_id = s.segment_id
      LEFT JOIN (
        SELECT segment_id, COUNT(*) AS active_incidents
        FROM incidents
        WHERE status <> 'cleared' AND segment_id IS NOT NULL
        GROUP BY segment_id
      ) ic ON ic.segment_id = s.segment_id`);

    const ranked = rows.map((r) => {
      const limit = Number(r.speed_limit_kmh || 0);
      const speed = r.latest_speed == null ? limit : Number(r.latest_speed);
      const shortfallPct = limit > 0 ? Math.max(0, (limit - speed) / limit) : 0;
      const statusScore = r.status === 'closed' ? 50 : r.status === 'restricted' ? 25 : 0;
      const score = statusScore + shortfallPct * 30 + Number(r.active_incidents || 0) * 10;
      return { ...r, priority_score: Number(score.toFixed(1)) };
    }).sort((a, b) => b.priority_score - a.priority_score);

    res.json(ranked.slice(0, 8));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load watchlist' });
  }
});

router.get('/sensor-status', async (req, res) => {
  try {
    const [summary, sensors] = await Promise.all([
      db.query(`
        SELECT status, COUNT(*) AS count
        FROM sensors
        GROUP BY status
        ORDER BY status`),
      db.query(`
        SELECT se.sensor_id, se.segment_id, se.sensor_type, se.status,
               se.last_seen_at, rs.name AS road_name
        FROM sensors se
        JOIN road_segments rs ON rs.segment_id = se.segment_id
        ORDER BY se.status, se.sensor_id`),
    ]);
    res.json({ summary, sensors });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load sensor status' });
  }
});

router.get('/fines', async (req, res) => {
  try {
    res.json(await db.query('SELECT * FROM v_fine_summary ORDER BY total_fine DESC'));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load fine summary' });
  }
});

router.get('/incident-history', async (req, res) => {
  try {
    res.json(await db.query(`
      SELECT i.incident_id, i.incident_type, i.severity, i.description,
             i.status, i.reported_at, i.cleared_at, rs.name AS segment_name
      FROM incidents i
      LEFT JOIN road_segments rs ON rs.segment_id = i.segment_id
      WHERE i.status = 'cleared'
      ORDER BY COALESCE(i.cleared_at, i.reported_at) DESC
      LIMIT 30`));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load incident history' });
  }
});

router.get('/activity', async (req, res) => {
  try {
    res.json(await db.query(`
      SELECT a.audit_id, a.entity_type, a.entity_id, a.action, a.details,
             a.created_at, u.full_name AS actor
      FROM audit_logs a
      LEFT JOIN users u ON u.user_id = a.user_id
      ORDER BY a.created_at DESC, a.audit_id DESC
      LIMIT 50`));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load activity log' });
  }
});

module.exports = router;
