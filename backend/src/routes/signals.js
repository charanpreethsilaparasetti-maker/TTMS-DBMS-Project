const express = require('express');
const router = express.Router();
const db = require('../db');
const { logAction } = require('../audit');

router.get('/', async (req, res) => {
  try {
    const rows = await db.query('SELECT * FROM v_signal_overview ORDER BY signal_id');
    res.json(rows.map((r) => ({
      ...r,
      location: { type: 'Point', coordinates: [Number(r.longitude), Number(r.latitude)] },
    })));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to fetch signals' });
  }
});

router.patch('/:id', async (req, res) => {
  const { mode } = req.body;
  if (!['fixed', 'adaptive', 'flash', 'manual', 'off'].includes(mode)) {
    return res.status(400).json({ error: 'Invalid mode' });
  }
  try {
    const before = await db.query(
      `SELECT sg.mode, i.name AS intersection_name
       FROM traffic_signals sg
       JOIN intersections i ON i.intersection_id = sg.intersection_id
       WHERE sg.signal_id = ?`,
      [req.params.id]
    );
    if (!before.length) return res.status(404).json({ error: 'Signal not found' });

    await db.query('UPDATE traffic_signals SET mode = ? WHERE signal_id = ?', [mode, req.params.id]);
    await logAction({
      entityType: 'signal',
      entityId: Number(req.params.id),
      action: 'mode_changed',
      details: { intersection: before[0].intersection_name, from: before[0].mode, to: mode },
    });
    res.json({ signal_id: Number(req.params.id), mode });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to update signal' });
  }
});

module.exports = router;
