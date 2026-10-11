const express = require('express');
const router = express.Router();
const db = require('../db');

// GET /api/violations?plate=MP04  (SEARCH with LIKE, 3-table JOIN)
router.get('/', async (req, res) => {
  const plate = `%${(req.query.plate || '').trim()}%`;
  try {
    res.json(await db.query(
      `SELECT vi.violation_id, v.plate_number, v.owner_name, t.type_name, t.base_fine, vi.status, vi.occurred_at
       FROM violations vi
       JOIN vehicles v        ON v.vehicle_id = vi.vehicle_id
       JOIN violation_types t ON t.type_id    = vi.type_id
       WHERE v.plate_number LIKE ?
       ORDER BY vi.occurred_at DESC`, [plate]));
  } catch (err) { console.error(err); res.status(500).json({ error: 'Failed to fetch violations' }); }
});

module.exports = router;
