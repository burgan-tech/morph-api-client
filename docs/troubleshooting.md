# Troubleshooting

Common errors and their fixes when running the Morph PoC.

---

## "Keycloak session is dead" in Simulation

**Error:**
> Keycloak session is dead (refresh: invalid_grant / Token is not active). Simulation stopped -- sign in again from Home.

**Cause:** Both `morph-auth/1fa` and `morph-auth/2fa` tokens failed authentication in the same simulation tick. This happens when:
- You haven't signed in yet (no tokens at all)
- Your tokens expired and the refresh token's idle timeout has passed

**Fix:**
1. Go to the Home page
2. Click **Keycloak login** on the Login (2fa) row
3. Sign in with `testuser / TestPass123!`
4. (Optional) Click **Exchange** on the Session (1fa) row, or let the simulation auto-exchange
5. Click **Start** on the Simulation panel

If tokens expire too quickly during development, use longer lifetimes:
```bash
make keycloak-restore-tokens
```

---

## "unauthorized_client / Invalid client credentials"

**Error:**
```json
{
  "error": "unauthorized_client",
  "error_description": "Invalid client or Invalid client credentials"
}
```

**Cause:** The `VITE_*_CLIENT_SECRET` environment variables are missing or empty. The SDK sends blank credentials to Keycloak.

**Fix:**
1. Ensure `poc/ts-vue/.env` exists:
   ```bash
   cp poc/ts-vue/.env.example poc/ts-vue/.env
   ```
2. Verify it contains:
   ```
   VITE_DEVICE_CLIENT_SECRET=morph-device-secret
   VITE_LOGIN_CLIENT_SECRET=morph-login-secret
   VITE_SESSION_CLIENT_SECRET=morph-session-secret
   ```
3. **Restart the Vite dev server** (Vite reads `.env` only at startup):
   ```bash
   make down
   make dev
   ```

---

## "Realm 'morph' not found"

**Error:**
> Realm 'morph' not found (HTTP 404). This means --import-realm did not run or the volume has stale data.

**Cause:** The Keycloak Docker container has stale volume data from a previous run, or the realm JSON was not imported.

**Fix:** Destroy volumes and re-run:
```bash
make keycloak-down
docker compose -f poc/keycloak/docker-compose.yml down -v
make up
```

---

## "Port 5173 is already in use"

**Error:**
```
Error: Port 5173 is already in use
```

**Cause:** A previous Vite process is still running on port 5173.

**Fix:**
```bash
lsof -ti :5173 | xargs kill -9
make dev
```

`make up` does this automatically before starting.

---

## "Port 3000 is already in use" / Mock API won't start

**Cause:** A previous mock API process is still running.

**Fix:**
```bash
lsof -ti :3000 | xargs kill -9
make mock-api
```

---

## redirect_uri_mismatch from Keycloak

**Error:** Keycloak shows "Invalid parameter: redirect_uri" after the login form.

**Cause:** The OAuth redirect URI sent by the SDK doesn't match what's registered on the Keycloak client.

**Fix:**
1. Re-run the Keycloak setup to update redirect URIs:
   ```bash
   make keycloak-setup
   ```
2. Ensure you're accessing the Vue app at `http://127.0.0.1:5173` or `http://localhost:5173` (both are registered).
3. If using a different host/port, add it to the `redirectUris` list in `poc/keycloak/setup.sh` and re-run.

---

## CORS errors on token endpoint

**Error:** Browser console shows CORS errors when the SDK tries to call the Keycloak token endpoint.

**Cause:** In development, the browser blocks cross-origin POST requests to `localhost:8080`. The Vite proxy (`/__keycloak`) solves this, but only works when the Vite dev server is running.

**Fix:**
- Make sure you are running the app with `make dev` or `make up` (not a static build)
- The SDK config sets `tokenHttpBaseUrl` to the Vite proxy path automatically in dev mode

---

## Token exchange fails

**Error:** Clicking **Exchange** on the 1fa row fails, or the simulation shows AUTH for 1fa steps.

**Cause:** Token exchange requires a valid `morph-auth/2fa` access token. The 2fa token is sent as the `subject_token` in the exchange request.

**Fix:**
1. Sign in with Keycloak first (click **Keycloak login** on the 2fa row)
2. Verify the 2fa row shows **OK**
3. Then click **Exchange** on the 1fa row

If the 2fa token has expired, sign in again.

---

## Keycloak container won't start

**Cause:** Docker is not running, or port 8080 is occupied.

**Fix:**
1. Start Docker Desktop (or the Docker daemon)
2. Check if port 8080 is in use:
   ```bash
   lsof -i :8080
   ```
3. Start Keycloak:
   ```bash
   make keycloak-up
   ```
4. Check logs if it fails:
   ```bash
   make keycloak-logs
   ```

---

## "Keycloak not ready after 60s"

**Cause:** Keycloak is taking longer than expected to start (first run pulls a ~500MB Docker image).

**Fix:**
1. Check if the image is still downloading:
   ```bash
   docker compose -f poc/keycloak/docker-compose.yml logs -f
   ```
2. Wait for the message "Keycloak ... started in ..." then re-run:
   ```bash
   make keycloak-setup
   make mock-api &
   make dev
   ```

---

## Google login button is disabled

**Cause:** The `VITE_GOOGLE_CLIENT_ID` and `VITE_GOOGLE_CLIENT_SECRET` variables are not set. Both are required for the Google provider to be enabled.

**Fix:** See [docs/poc/google-setup.md](poc/google-setup.md) for Google Cloud Console setup instructions. Add the credentials to `poc/ts-vue/.env`:
```
VITE_GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
VITE_GOOGLE_CLIENT_SECRET=GOCSPX-your-secret
```

Then restart the Vite dev server.

---

## All tests pass but the Vue app doesn't work

If `make keycloak-test` passes (all 5 OAuth flow tests) but the Vue app shows errors:

1. **Check `.env`**: The test script uses hardcoded secrets; the Vue app needs `VITE_*` variables
2. **Restart Vite**: Env changes require a server restart
3. **Clear browser storage**: Open DevTools > Application > Session Storage > clear `morph-poc:tk:*` entries
4. **Hard refresh**: `Cmd+Shift+R` / `Ctrl+Shift+R` to bypass cache

---

## Useful commands

| Command | Purpose |
|---------|---------|
| `make help` | List all Makefile targets |
| `make keycloak-test` | Run OAuth flow smoke tests |
| `make keycloak-logs` | Tail Keycloak container logs |
| `make keycloak-setup` | Re-run full Keycloak setup |
| `make keycloak-short-tokens` | Apply short token lifetimes (15s/30s/20s) |
| `make keycloak-restore-tokens` | Restore long-lived token lifetimes |
| `make down` | Stop all services |
| `make clean` | Remove all node_modules and dist |
