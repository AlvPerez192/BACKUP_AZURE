// =============================================================================
// TFG Multi-Cloud: app web con formulario CRUD de clientes
// =============================================================================
// La misma imagen Docker corre tanto en EKS (sobre RDS) como en la VM Docker
// del pilot light (sobre Azure DB). Lo unico que cambia son las variables de
// entorno DB_HOST, DB_USER, DB_PASSWORD, DB_NAME.
//
// Endpoints:
//   GET  /          -> listado de clientes + formulario
//   POST /clientes  -> crear cliente
//   POST /clientes/:id/delete -> borrar cliente
//   GET  /health    -> health check (usado por K8s liveness/readiness y
//                      por el workflow health-check-aws.yml)
// =============================================================================

const express = require('express');
const mysql   = require('mysql2/promise');
const path    = require('path');

const app  = express();
const PORT = parseInt(process.env.APP_PORT || '3000', 10);

// Pool de conexiones (mejor que conexiones one-shot bajo carga)
const pool = mysql.createPool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '3306', 10),
  user:     process.env.DB_USER     || 'admin',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME     || 'tfg_app',
  waitForConnections: true,
  connectionLimit:    10,
  queueLimit:         0,
  // SSL: en RDS de produccion deberia ir activado. En esta prueba lo dejamos
  // off para simplificar (RDS Academy y Azure DB ambas aceptan conexion
  // sin SSL en tier basico).
});

// Detectar en que cloud estamos (para mostrarlo en la UI)
const CLOUD = process.env.CLOUD_PROVIDER || 'unknown';

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

// -----------------------------------------------------------------------------
// Health check
// -----------------------------------------------------------------------------
// IMPORTANTE: este endpoint lo usan:
//   - Kubernetes livenessProbe / readinessProbe
//   - El workflow health-check-aws.yml que dispara el failover
// Por eso debe verificar la conexion a BD, no solo devolver 200.
app.get('/health', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT 1 AS ok');
    res.status(200).json({
      status: 'healthy',
      cloud:  CLOUD,
      db:     'connected',
      check:  rows[0].ok === 1,
    });
  } catch (err) {
    console.error('[health] DB error:', err.message);
    res.status(503).json({
      status: 'unhealthy',
      cloud:  CLOUD,
      db:     'disconnected',
      error:  err.message,
    });
  }
});

// -----------------------------------------------------------------------------
// CRUD de clientes
// -----------------------------------------------------------------------------
app.get('/', async (req, res) => {
  try {
    const [clientes] = await pool.query(
      'SELECT id, nombre, email, telefono, empresa, created_at FROM clientes ORDER BY id DESC'
    );
    res.render('index', { clientes, cloud: CLOUD, error: null });
  } catch (err) {
    console.error('[GET /] DB error:', err.message);
    res.status(500).render('index', { clientes: [], cloud: CLOUD, error: err.message });
  }
});

app.post('/clientes', async (req, res) => {
  const { nombre, email, telefono, empresa } = req.body;

  // Validacion minima
  if (!nombre || !email) {
    return res.redirect('/?error=nombre_y_email_obligatorios');
  }

  try {
    await pool.query(
      'INSERT INTO clientes (nombre, email, telefono, empresa) VALUES (?, ?, ?, ?)',
      [nombre, email, telefono || null, empresa || null]
    );
    res.redirect('/');
  } catch (err) {
    console.error('[POST /clientes] DB error:', err.message);
    res.redirect('/?error=' + encodeURIComponent(err.message));
  }
});

app.post('/clientes/:id/delete', async (req, res) => {
  try {
    await pool.query('DELETE FROM clientes WHERE id = ?', [req.params.id]);
    res.redirect('/');
  } catch (err) {
    console.error('[DELETE] DB error:', err.message);
    res.redirect('/?error=' + encodeURIComponent(err.message));
  }
});

// -----------------------------------------------------------------------------
// Arranque
// -----------------------------------------------------------------------------
app.listen(PORT, '0.0.0.0', () => {
  console.log(`[app] Escuchando en :${PORT}`);
  console.log(`[app] Cloud: ${CLOUD}`);
  console.log(`[app] DB: ${process.env.DB_HOST}:${process.env.DB_PORT || 3306}/${process.env.DB_NAME}`);
});

// Cerrar el pool limpiamente al recibir SIGTERM (importante en K8s)
process.on('SIGTERM', async () => {
  console.log('[app] SIGTERM recibido, cerrando pool...');
  await pool.end();
  process.exit(0);
});
