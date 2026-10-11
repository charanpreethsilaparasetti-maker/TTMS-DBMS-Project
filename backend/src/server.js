const path = require('path');
const express = require('express');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

app.get('/api/health', async (req, res) => {
  try {
    await require('./db').query('SELECT 1');
    res.json({ status: 'ok', database: 'mysql' });
  } catch (e) {
    res.status(500).json({ status: 'db error', message: e.message });
  }
});

app.use('/api/segments', require('./routes/segments'));
app.use('/api/sensors', require('./routes/sensors'));
app.use('/api/incidents', require('./routes/incidents'));
app.use('/api/signals', require('./routes/signals'));
app.use('/api/violations', require('./routes/violations'));
app.use('/api/dashboard', require('./routes/dashboard'));

app.use(express.static(path.join(__dirname, '..', '..', 'frontend')));

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`TTMS running at http://localhost:${PORT}`));
