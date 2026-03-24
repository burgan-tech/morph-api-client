const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const KC_URL = process.env.KC_URL || 'http://localhost:8080';
const KC_REALM = process.env.KC_REALM || 'morph';
const KC_ISSUER = `${KC_URL}/realms/${KC_REALM}`;
const PORT = process.env.PORT || 3000;

const keycloakJwks = jwksClient({
  jwksUri: `${KC_ISSUER}/protocol/openid-connect/certs`,
  cache: true,
  rateLimit: true,
});

function getSigningKey(header, callback) {
  keycloakJwks.getSigningKey(header.kid, (err, key) => {
    if (err) return callback(err);
    callback(null, key.getPublicKey());
  });
}

function requireKeycloakToken(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'missing_token', message: 'Authorization header required' });
  }

  const token = authHeader.split(' ')[1];
  jwt.verify(token, getSigningKey, {
    issuer: KC_ISSUER,
    algorithms: ['RS256'],
  }, (err, decoded) => {
    if (err) {
      const isUpstream = /ECONNREFUSED|ENOTFOUND|ETIMEDOUT|network|socket|getaddrinfo/i.test(err.message);
      if (isUpstream) {
        return res.status(502).json({ error: 'upstream_unreachable', message: `Keycloak JWKS unavailable: ${err.message}` });
      }
      return res.status(401).json({ error: 'invalid_token', message: err.message });
    }
    req.user = decoded;
    req.authLevel = decoded.azp === 'morph-session' ? '1fa'
                   : decoded.azp === 'morph-login' ? '2fa'
                   : decoded.azp === 'morph-device' ? 'device'
                   : decoded.azp;
    next();
  });
}

// ---------------------------------------------------------------------------
// Google token validation (via tokeninfo endpoint)
// ---------------------------------------------------------------------------
async function requireGoogleToken(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'missing_token', message: 'Authorization header required' });
  }
  const token = authHeader.split(' ')[1];
  let response;
  try {
    response = await fetch(`https://oauth2.googleapis.com/tokeninfo?access_token=${token}`);
  } catch (err) {
    return res.status(502).json({ error: 'upstream_unreachable', message: `Google tokeninfo unavailable: ${err.message}` });
  }
  if (!response.ok) {
    let body;
    try { body = await response.json(); } catch { body = {}; }
    const hint = body.error_description || body.error || `HTTP ${response.status}`;
    return res.status(401).json({ error: 'invalid_token', message: `Google rejected token: ${hint}` });
  }
  req.user = await response.json();
  req.authLevel = 'google';
  next();
}

// ===========================================================================
// Public endpoints
// ===========================================================================

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), keycloak: KC_ISSUER });
});

app.get('/public/config', (_req, res) => {
  res.json({
    appName: 'Morph PoC',
    version: '0.1.0',
    features: ['accounts', 'transfers', 'identity'],
    maintenance: false,
  });
});

/** Intentional 404 for PoC /simulation probe (JSON body). */
app.get('/sim/not-found', (_req, res) => {
  res.status(404).json({ error: 'not_found', hint: 'simulation probe' });
});

// ===========================================================================
// Protected endpoints
// ===========================================================================

app.get('/accounts', requireKeycloakToken, (req, res) => {
  res.json({
    accounts: [
      { id: 'ACC-001', name: 'Main Account', balance: 15420.50, currency: 'TRY' },
      { id: 'ACC-002', name: 'Savings', balance: 85000.00, currency: 'TRY' },
      { id: 'ACC-003', name: 'USD Account', balance: 2340.00, currency: 'USD' },
    ],
    authenticatedAs: req.user.sub,
    authLevel: req.authLevel,
    client: req.user.azp,
  });
});

app.post('/transfers', requireKeycloakToken, (req, res) => {
  const { fromAccount, toAccount, amount, currency } = req.body || {};
  res.json({
    transferId: `TRF-${Date.now()}`,
    fromAccount: fromAccount || 'ACC-001',
    toAccount: toAccount || 'ACC-002',
    amount: amount || 100,
    currency: currency || 'TRY',
    status: 'completed',
    timestamp: new Date().toISOString(),
    authenticatedAs: req.user.sub,
    authLevel: req.authLevel,
  });
});

app.get('/profile', requireKeycloakToken, (req, res) => {
  res.json({
    sub: req.user.sub,
    preferredUsername: req.user.preferred_username,
    email: req.user.email,
    name: req.user.name,
    authLevel: req.authLevel,
  });
});

// ===========================================================================
// Google-authenticated endpoints
// ===========================================================================

app.get('/identity/verify', requireGoogleToken, (req, res) => {
  res.json({
    verified: true,
    provider: 'google',
    email: req.user.email,
    sub: req.user.sub,
    authLevel: req.authLevel,
    timestamp: new Date().toISOString(),
  });
});

// ===========================================================================
// Callback helpers (for browser-based testing)
// ===========================================================================

app.get('/callback/keycloak', (req, res) => {
  const { code, error, error_description } = req.query;
  if (error) return res.status(400).json({ error, error_description });
  res.json({
    message: 'Authorization code received. Exchange it at the Keycloak token endpoint.',
    code,
    tokenEndpoint: `${KC_ISSUER}/protocol/openid-connect/token`,
    hint: 'POST with grant_type=authorization_code, code, redirect_uri, client_id, client_secret',
  });
});

app.get('/callback/google', (req, res) => {
  const { code, error } = req.query;
  if (error) return res.status(400).json({ error });
  res.json({
    message: 'Google authorization code received.',
    code,
    tokenEndpoint: 'https://oauth2.googleapis.com/token',
  });
});

// ===========================================================================
// JWKS proxy (for SDK to validate tokens from mock API if needed)
// ===========================================================================

app.get('/.well-known/jwks.json', async (_req, res) => {
  try {
    const response = await fetch(`${KC_ISSUER}/protocol/openid-connect/certs`);
    const jwks = await response.json();
    res.json(jwks);
  } catch (err) {
    res.status(502).json({ error: 'jwks_proxy_error', message: err.message });
  }
});

// ===========================================================================
// Start
// ===========================================================================

app.listen(PORT, () => {
  console.log(`Morph Mock API running on http://localhost:${PORT}`);
  console.log(`Keycloak: ${KC_ISSUER}`);
  console.log('');
  console.log('Public:');
  console.log('  GET  /health');
  console.log('  GET  /public/config');
  console.log('  GET  /sim/not-found  (404 probe)');
  console.log('');
  console.log('Protected (Keycloak JWT):');
  console.log('  GET  /accounts');
  console.log('  POST /transfers');
  console.log('  GET  /profile');
  console.log('');
  console.log('Google-authenticated:');
  console.log('  GET  /identity/verify');
  console.log('');
  console.log('Callbacks:');
  console.log('  GET  /callback/keycloak');
  console.log('  GET  /callback/google');
});
