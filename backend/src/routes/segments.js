const express = require('express');
const router = express.Router();
const db = require('../db');
const { logAction } = require('../audit');

router.get('/', async (req, res) => {
  try {
    const rows = await db.query(`
      SELECT s.segment_id, s.name, s.road_class, s.length_m, s.lanes, s.speed_limit_kmh, s.status,
             a.latitude AS from_lat, a.longitude AS from_lng,
             b.latitude AS to_lat,   b.longitude AS to_lng
      FROM road_segments s
      JOIN intersections a ON a.intersection_id = s.from_intersection
      JOIN intersections b ON b.intersection_id = s.to_intersection
      ORDER BY s.segment_id`);
    res.json(rows.map((r) => ({
      segment_id: r.segment_id,
      name: r.name,
      road_class: r.road_class,
      length_m: r.length_m,
      lanes: r.lanes,
      speed_limit_kmh: r.speed_limit_kmh,
      status: r.status,
      geometry: {
        type: 'LineString',
        coordinates: [[Number(r.from_lng), Number(r.from_lat)], [Number(r.to_lng), Number(r.to_lat)]],
      },
    })));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to fetch segments' });
  }
});

router.patch('/:id', async (req, res) => {
  const { status } = req.body;
  if (!['open', 'restricted', 'closed'].includes(status)) {
    return res.status(400).json({ error: 'Invalid status' });
  }
  try {
    const before = await db.query('SELECT name, status FROM road_segments WHERE segment_id = ?', [req.params.id]);
    if (!before.length) return res.status(404).json({ error: 'Segment not found' });

    await db.query('UPDATE road_segments SET status = ? WHERE segment_id = ?', [status, req.params.id]);
    await logAction({
      entityType: 'road_segment',
      entityId: Number(req.params.id),
      action: 'status_changed',
      details: { name: before[0].name, from: before[0].status, to: status },
    });
    res.json({ segment_id: Number(req.params.id), status });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to update segment' });
  }
});

module.exports = router;
