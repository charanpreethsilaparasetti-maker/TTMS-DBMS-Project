const db = require('./db');

async function logAction({
  userId = 2,
  entityType,
  entityId = null,
  action,
  details = {},
}) {
  try {
    await db.query(
      `INSERT INTO audit_logs (user_id, entity_type, entity_id, action, details)
       VALUES (?, ?, ?, ?, ?)`,
      [userId, entityType, entityId, action, JSON.stringify(details)]
    );
  } catch (err) {
    // Audit logging must not break the requested dashboard action.
    console.warn('Audit log write failed:', err.message);
  }
}

module.exports = { logAction };
