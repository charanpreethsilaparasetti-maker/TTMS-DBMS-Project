# Traffic & Transportation Management System (TTMS) - MySQL edition

DBMS course project, IIIT Bhopal (Monsoon 2026-27).
Stack: **MySQL 8** + **Node.js / Express** (REST API with mysql2) + HTML/CSS/JS dashboard (Leaflet map).

## Folder layout
```
ttms/
├── db/ttms_mysql.sql        # complete MySQL script: tables, constraints, data, queries, views, triggers
├── backend/                 # Express API (src/server.js, src/db.js, src/routes/*.js)
└── frontend/                # dashboard (index.html, css/style.css, js/app.js)
```

## Run it on Linux

1. Load the database (8 errors at the very end are expected - they are the constraint tests):
   ```bash
   sudo mysql --force < db/ttms_mysql.sql
   ```
2. Create a normal MySQL user for the app (root uses socket login on Ubuntu):
   ```bash
   sudo mysql -e "CREATE USER IF NOT EXISTS 'ttms_user'@'localhost' IDENTIFIED BY 'ttms_pass'; GRANT ALL ON ttms.* TO 'ttms_user'@'localhost';"
   ```
3. Start the app (needs Node.js 18+; if missing: `sudo apt install nodejs npm`):
   ```bash
   cd backend
   cp .env.example .env
   npm install
   npm start
   ```
4. Open **http://localhost:4000** in the browser (the map tiles need internet).

## What the dashboard does (database operations)
| Operation | Where | SQL used |
|---|---|---|
| INSERT | "Report an incident" form | `INSERT INTO incidents ...` (trigger `trg_incident_alert` fires for severity >= 4) |
| SELECT / SEARCH | "Search violations by plate" | 3-table JOIN with `LIKE` |
| UPDATE | status dropdown on an incident; mode dropdown on a signal | `UPDATE incidents ...`, `UPDATE traffic_signals ...` (trigger `trg_incident_cleared`) |
| DELETE | "Delete" button on an incident | `DELETE FROM incidents ...` (alerts removed by ON DELETE CASCADE) |
| VIEWS | KPIs, signal list, latest readings | `v_latest_readings`, `v_signal_overview` |

API health check: http://localhost:4000/api/health
