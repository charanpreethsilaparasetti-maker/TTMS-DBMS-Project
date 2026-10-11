const express = require('express');
const router = express.Router();
const db = require('../db');
const { logAction } = require('../audit');

const toRow = (r) => ({
  ...r,
  location: r.latitude != null
    ? { type: 'Point', coordinates: [Number(r.longitude), Number(r.latitude)] }
    : null,
});

router.get('/', async (req, res) => {
  try {
    const base = `SELECT incident_id, segment_id, incident_type, severity, latitude, longitude,
                         description, status, reported_at, cleared_at FROM incidents`;
    const rows = req.query.status
      ? await db.query(`${base} WHERE status = ? ORDER BY reported_at DESC`, [req.query.status])
      : await db.query(`${base} ORDER BY reported_at DESC`);
    res.json(rows.map(toRow));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to fetch incidents' });
  }
});

router.post('/', async (req, res) => {
  const { segment_id, incident_type, severity, description, lat, lng } = req.body;
  if (!incident_type || !severity) {
    return res.status(400).json({ error: 'incident_type and severity are required' });
  }
  try {
    const r = await db.query(
      `INSERT INTO incidents (segment_id, incident_type, severity, latitude, longitude, description, reported_by)
       VALUES (?, ?, ?, ?, ?, ?, 2)`,
      [segment_id || null, incident_type, severity, lat ?? null, lng ?? null, description || null]
    );
    await logAction({
      entityType: 'incident',
      entityId: r.insertId,
      action: 'created',
      details: { segment_id, incident_type, severity, description, lat, lng },
    });
    res.status(201).json({ incident_id: r.insertId });
  } catch (err) {
    console.error(err);
    res.status(400).json({ error: err.sqlMessage || 'Failed to create incident' });
  }
});

router.patch('/:id', async (req, res) => {
  const { status } = req.body;
  if (!['reported', 'verified', 'responding', 'cleared'].includes(status)) {
    return res.status(400).json({ error: 'Invalid status' });
  }
  try {
    const before = await db.query('SELECT status FROM incidents WHERE incident_id = ?', [req.params.id]);
    if (!before.length) return res.status(404).json({ error: 'Incident not found' });

    await db.query('UPDATE incidents SET status = ? WHERE incident_id = ?', [status, req.params.id]);
    await logAction({
      entityType: 'incident',
      entityId: Number(req.params.id),
      action: 'status_changed',
      details: { from: before[0].status, to: status },
    });
    res.json({ incident_id: Number(req.params.id), status });
  } catch (err) {
    console.error(err);
    res.status(400).json({ error: err.sqlMessage || 'Failed to update incident' });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const before = await db.query(
      'SELECT incident_type, severity, description, status FROM incidents WHERE incident_id = ?',
      [req.params.id]
    );
    if (!before.length) return res.status(404).json({ error: 'Incident not found' });

    await db.query('DELETE FROM incidents WHERE incident_id = ?', [req.params.id]);
    await logAction({
      entityType: 'incident',
      entityId: Number(req.params.id),
      action: 'deleted',
      details: before[0],
    });
    res.json({ deleted: Number(req.params.id) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to delete incident' });
  }
});

module.exports = router;
