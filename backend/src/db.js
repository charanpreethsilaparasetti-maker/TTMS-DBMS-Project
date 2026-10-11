// MySQL connection pool (mysql2). All queries use ? placeholders = parameterized SQL,
// which prevents SQL injection.
const mysql = require('mysql2/promise');
require('dotenv').config();

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'ttms_user',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'ttms',
  waitForConnections: true,
  connectionLimit: 10,
  dateStrings: true,
});

module.exports = {
  query: async (sql, params) => (await pool.query(sql, params))[0],
  pool,
};
