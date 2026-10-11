const API_BASE = window.TTMS_API_BASE || '/api';
const COLORS = ['#4fb3ff','#51d0a8','#ffb454','#e66a7a','#aa8cff','#6fd6e7','#f07ad7','#9ad45c','#ff8f5e','#8aa4ff'];
const STATUS_COLOR = { open: '#51d0a8', restricted: '#ffb454', closed: '#e66a7a' };

let map, segmentLayer, incidentLayer, selectedPinMarker;
let selectedPin = null;
let segmentsCache = [];
let speedChart, volumeChart, fineChart;

async function fetchJSON(path, options) {
  const res = await fetch(`${API_BASE}${path}`, options);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || `${path} returned ${res.status}`);
  return body;
}

function setConnection(ok) {
  document.getElementById('connDot').className = `dot ${ok ? 'live' : 'down'}`;
  document.getElementById('connLabel').textContent = ok ? 'API connected' : 'API unavailable';
}

function initMap() {
  map = L.map('map').setView([23.232, 77.415], 13);
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap contributors', maxZoom: 19,
  }).addTo(map);
  segmentLayer = L.layerGroup().addTo(map);
  incidentLayer = L.layerGroup().addTo(map);
  map.on('click', (e) => {
    selectedPin = { lat: e.latlng.lat, lng: e.latlng.lng };
    if (selectedPinMarker) selectedPinMarker.remove();
    selectedPinMarker = L.marker(e.latlng).addTo(map).bindPopup('Selected incident location').openPopup();
    document.getElementById('pinNote').textContent = `Selected pin: ${e.latlng.lat.toFixed(5)}, ${e.latlng.lng.toFixed(5)}`;
  });
}

function renderMap(segments, incidents) {
  segmentLayer.clearLayers();
  incidentLayer.clearLayers();
  const bounds = [];
  segments.forEach((seg) => {
    const latlngs = seg.geometry.coordinates.map(([lng, lat]) => [lat, lng]);
    bounds.push(...latlngs);
    L.polyline(latlngs, { color: STATUS_COLOR[seg.status] || '#87909c', weight: 6, opacity: .9 })
      .bindPopup(`<strong>${seg.name}</strong><br>${seg.road_class}<br>Status: ${seg.status}<br>Limit: ${seg.speed_limit_kmh} km/h`)
      .addTo(segmentLayer);
  });
  incidents.filter(i => i.status !== 'cleared' && i.location).forEach((inc) => {
    const [lng, lat] = inc.location.coordinates;
    L.circleMarker([lat, lng], { radius: 7, color: '#e66a7a', fillColor: '#e66a7a', fillOpacity: .9 })
      .bindPopup(`<strong>${inc.incident_type}</strong><br>${inc.description || ''}<br>Severity ${inc.severity} - ${inc.status}`)
      .addTo(incidentLayer);
  });
  if (bounds.length) map.fitBounds(bounds, { padding: [30, 30] });
}

function midpoint(seg) {
  const [[lng1, lat1], [lng2, lat2]] = seg.geometry.coordinates;
  return { lat: (lat1 + lat2) / 2, lng: (lng1 + lng2) / 2 };
}

function renderKPIs(s) {
  document.getElementById('kpiIncidents').textContent = s.active_incidents;
  document.getElementById('kpiSpeed').textContent = s.avg_network_speed == null ? '-' : `${s.avg_network_speed} km/h`;
  document.getElementById('kpiSensors').textContent = `${s.sensors_active}/${s.sensors_total}`;
  document.getElementById('kpiSignals').textContent = `${s.adaptive_signals}/${s.signals_total}`;
}

function renderWatchlist(rows) {
  document.getElementById('watchlist').innerHTML = rows.length ? rows.map((r, i) => `
    <div class="list-row">
      <span><strong>${i + 1}. ${r.name}</strong><small>${r.status} | speed ${r.latest_speed ?? '-'} / ${r.speed_limit_kmh} km/h | incidents ${r.active_incidents}</small></span>
      <b class="score">${r.priority_score}</b>
    </div>`).join('') : '<p class="muted">No priority corridors.</p>';
}

function renderCorridors(rows) {
  document.getElementById('corridorBody').innerHTML = rows.map(r => `
    <tr><td>${r.name}</td><td>${r.road_class}</td><td>${r.lanes}</td><td><span class="pill ${r.status}">${r.status}</span></td><td>${r.speed_limit_kmh} km/h</td><td>${r.latest_speed ?? '-'}</td><td>${r.vehicles_per_hr}</td></tr>`).join('');
}

function renderSensors(data) {
  const mapCounts = Object.fromEntries(data.summary.map(x => [x.status, Number(x.count)]));
  document.getElementById('sensorSummary').innerHTML = ['active','faulty','inactive'].map(k => `<div><span>${k}</span><strong>${mapCounts[k] || 0}</strong></div>`).join('');
  document.getElementById('sensorList').innerHTML = data.sensors.map(s => `<div class="list-row"><span><strong>#${s.sensor_id} ${s.sensor_type}</strong><small>${s.road_name}</small></span><span class="pill ${s.status}">${s.status}</span></div>`).join('');
}

function sevClass(n) { return n >= 4 ? 'danger' : n >= 2 ? 'warn' : 'ok'; }

function renderIncidents(rows) {
  const active = rows.filter(i => i.status !== 'cleared');
  document.getElementById('activeIncidents').innerHTML = active.length ? active.map(i => `
    <div class="list-row ${sevClass(i.severity)}"><span><strong>#${i.incident_id} ${i.incident_type}</strong><small>${i.description || 'No description'} | severity ${i.severity}</small></span><span class="row-actions"><select onchange="updateIncident(${i.incident_id},this.value)">${['reported','verified','responding','cleared'].map(s => `<option ${s === i.status ? 'selected' : ''}>${s}</option>`).join('')}</select><button class="danger-btn" onclick="deleteIncident(${i.incident_id})">Delete</button></span></div>`).join('') : '<p class="muted">No active incidents.</p>';
}

function renderHistory(rows) {
  document.getElementById('incidentHistory').innerHTML = rows.length ? rows.map(i => `<div class="list-row"><span><strong>#${i.incident_id} ${i.incident_type}</strong><small>${i.segment_name || 'Unknown road'} | cleared ${i.cleared_at || '-'}</small></span><span class="pill">cleared</span></div>`).join('') : '<p class="muted">No cleared incidents.</p>';
}

function renderSignals(rows) {
  document.getElementById('signalControls').innerHTML = rows.map(s => `<div class="list-row"><span><strong>${s.intersection_name}</strong><small>${s.controller_model} | ${s.status}</small></span><select onchange="updateSignal(${s.signal_id},this.value)">${['fixed','adaptive','flash','manual','off'].map(m => `<option ${m === s.mode ? 'selected' : ''}>${m}</option>`).join('')}</select></div>`).join('');
}

function renderRoadControls(rows) {
  document.getElementById('roadControls').innerHTML = rows.map(s => `<div class="list-row"><span><strong>${s.name}</strong><small>${s.road_class}</small></span><select onchange="updateRoad(${s.segment_id},this.value)">${['open','restricted','closed'].map(st => `<option ${st === s.status ? 'selected' : ''}>${st}</option>`).join('')}</select></div>`).join('');
}

function renderActivity(rows) {
  document.getElementById('activityLog').innerHTML = rows.length ? rows.map(a => {
    let details = a.details;
    if (typeof details === 'string') { try { details = JSON.parse(details); } catch {} }
    const detailText = details && typeof details === 'object' ? Object.entries(details).map(([k,v]) => `${k}: ${v}`).join(', ') : '';
    return `<div class="list-row"><span><strong>${a.action}</strong><small>${a.entity_type}${a.entity_id ? ` #${a.entity_id}` : ''}${detailText ? ` | ${detailText}` : ''}</small></span><time>${a.created_at}</time></div>`;
  }).join('') : '<p class="muted">No activity yet.</p>';
}

function lineChart(rows) {
  const labels = [...new Set(rows.map(r => r.bucket))];
  const roads = [...new Map(rows.map(r => [r.segment_id, r.name])).entries()];
  const datasets = roads.map(([id, name], idx) => ({
    label: name,
    data: labels.map(label => {
      const x = rows.find(r => Number(r.segment_id) === Number(id) && r.bucket === label);
      return x ? Number(x.avg_speed) : null;
    }),
    borderColor: COLORS[idx % COLORS.length],
    backgroundColor: COLORS[idx % COLORS.length],
    tension: .3,
    spanGaps: true,
  }));
  if (speedChart) speedChart.destroy();
  speedChart = new Chart(document.getElementById('speedChart'), { type: 'line', data: { labels, datasets }, options: chartOptions('Average speed (km/h)') });
}

function barChart(canvasId, oldChart, labels, datasets, title) {
  if (oldChart) oldChart.destroy();
  return new Chart(document.getElementById(canvasId), { type: 'bar', data: { labels, datasets }, options: chartOptions(title) });
}

function chartOptions(title) {
  return {
    responsive: true,
    maintainAspectRatio: false,
    plugins: { legend: { labels: { color: '#dfe6ef' } }, title: { display: false, text: title } },
    scales: {
      x: { ticks: { color: '#9aa6b2', maxRotation: 45, minRotation: 0 }, grid: { color: '#28313c' } },
      y: { ticks: { color: '#9aa6b2' }, grid: { color: '#28313c' }, beginAtZero: true },
    },
  };
}

async function loadTrends() {
  const hours = document.getElementById('trendRange').value;
  const rows = await fetchJSON(`/dashboard/trends?hours=${hours}`);
  lineChart(rows);
}

async function refresh() {
  try {
    const [segments, incidents, signals, summary, corridors, watchlist, hourly, sensorStatus, fines, history, activity] = await Promise.all([
      fetchJSON('/segments'), fetchJSON('/incidents'), fetchJSON('/signals'), fetchJSON('/dashboard/summary'),
      fetchJSON('/dashboard/corridors'), fetchJSON('/dashboard/watchlist'), fetchJSON('/dashboard/hourly-volume?hours=24'),
      fetchJSON('/dashboard/sensor-status'), fetchJSON('/dashboard/fines'), fetchJSON('/dashboard/incident-history'), fetchJSON('/dashboard/activity'),
    ]);
    setConnection(true);
    segmentsCache = segments;
    renderMap(segments, incidents);
    renderKPIs(summary);
    renderCorridors(corridors);
    renderWatchlist(watchlist);
    renderSensors(sensorStatus);
    renderIncidents(incidents);
    renderHistory(history);
    renderSignals(signals);
    renderRoadControls(segments);
    renderActivity(activity);
    document.getElementById('segmentSelect').innerHTML = segments.map(s => `<option value="${s.segment_id}">${s.name}</option>`).join('');

    const volumeLabels = hourly.map(x => x.bucket);
    volumeChart = barChart('volumeChart', volumeChart, volumeLabels, [{ label: 'Vehicles', data: hourly.map(x => Number(x.vehicle_count)), backgroundColor: '#4fb3ff' }], 'Traffic volume');
    fineChart = barChart('fineChart', fineChart, fines.map(x => x.type_name), [
      { label: 'Total fine', data: fines.map(x => Number(x.total_fine)), backgroundColor: '#ffb454' },
      { label: 'Collected', data: fines.map(x => Number(x.collected)), backgroundColor: '#51d0a8' },
    ], 'Fine revenue');
    await loadTrends();
  } catch (err) {
    console.error(err);
    setConnection(false);
  }
}

async function updateIncident(id, status) {
  await fetchJSON(`/incidents/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ status }) });
  await refresh();
}
async function deleteIncident(id) {
  if (!confirm(`Delete incident #${id}?`)) return;
  await fetchJSON(`/incidents/${id}`, { method: 'DELETE' });
  await refresh();
}
async function updateSignal(id, mode) {
  await fetchJSON(`/signals/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ mode }) });
  await refresh();
}
async function updateRoad(id, status) {
  await fetchJSON(`/segments/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ status }) });
  await refresh();
}

async function submitIncident(e) {
  e.preventDefault();
  const f = e.target;
  const segmentId = Number(f.segment_id.value);
  const seg = segmentsCache.find(s => Number(s.segment_id) === segmentId);
  const loc = selectedPin || midpoint(seg);
  try {
    await fetchJSON('/incidents', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ segment_id: segmentId, incident_type: f.incident_type.value, severity: Number(f.severity.value), description: f.description.value, lat: loc.lat, lng: loc.lng }),
    });
    document.getElementById('formNote').textContent = 'Incident reported successfully.';
    selectedPin = null;
    if (selectedPinMarker) { selectedPinMarker.remove(); selectedPinMarker = null; }
    document.getElementById('pinNote').textContent = 'No custom pin selected.';
    f.description.value = '';
    await refresh();
  } catch (err) {
    document.getElementById('formNote').textContent = err.message;
  }
}

document.addEventListener('DOMContentLoaded', async () => {
  initMap();
  document.getElementById('incidentForm').addEventListener('submit', submitIncident);
  document.getElementById('trendRange').addEventListener('change', loadTrends);
  await refresh();
  setInterval(refresh, 30000);
});
