const express = require('express');
const router = express.Router();
const db = require('../db');
const { logAction } = require('../audit');

router.get('/', async (req, res) => {
  try {
    res.json(await db.query(`SELECT sensor_id, segment_id, sensor_type, status, latitude, longitude, last_seen_at
                             FROM sensors ORDER BY sensor_id`));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to fetch sensors' });
  }
});

router.get('/readings/latest', async (req, res) => {
  try {
    res.json(await db.query('SELECT * FROM v_latest_readings ORDER BY segment_id, sensor_id'));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to fetch readings' });
  }
});

router.post('/readings', async (req, res) => {
  const { sensor_id, vehicle_count, avg_speed_kmh, occupancy_pct } = req.body;
  if (!sensor_id) return res.status(400).json({ error: 'sensor_id is required' });
  try {
    const r = await db.query(
      `INSERT INTO traffic_readings (sensor_id, recorded_at, vehicle_count, avg_speed_kmh, occupancy_pct)
       VALUES (?, NOW(), ?, ?, ?)`,
      [sensor_id, vehicle_count, avg_speed_kmh, occupancy_pct]
    );
    await logAction({
      entityType: 'reading',
      entityId: r.insertId,
      action: 'created',
      details: { sensor_id, vehicle_count, avg_speed_kmh, occupancy_pct },
    });
    res.status(201).json({ reading_id: r.insertId });
  } catch (err) {
    console.error(err);
    res.status(400).json({ error: err.sqlMessage || 'Failed to record reading' });
  }
});

module.exports = router;
