# Google OAuth2 Setup Guide (PoC)

Google OAuth2 acts as the `google-auth` provider in the PoC — simulating an external identity provider.

## Prerequisites

- A Google account
- GCP project created (e.g., `morph-poc`)

---

## Step 1: Branding

1. Go to **Google Auth Platform > Branding** (left menu)
2. Fill in:
   - **App name**: `Morph PoC`
   - **User support email**: your email
   - **Developer contact email**: your email
3. **Save**

---

## Step 2: Audience

1. Go to **Audience** (left menu)
2. Select **External**
3. Add your Google email as a **Test user**
4. **Save**

---

## Step 3: Data Access (Scopes)

1. Go to **Data access** (left menu)
2. Click **Add or remove scopes**
3. Search and select:
   - `openid`
   - `userinfo.profile`
   - `userinfo.email`
4. **Save**

If this step is not available separately, scopes will be requested at runtime when the SDK initiates the auth flow — this step can be skipped.

---

## Step 4: Create OAuth Client

1. Go to **Clients** (left menu)
2. Click **Create OAuth client** (or the button at the top)
3. Fill in:
   - **Application type**: **Web application**
   - **Name**: `Morph PoC Client`
   - **Authorized JavaScript origins** (add each you use):
     - `http://localhost:5173`
     - `http://127.0.0.1:5173`
     - (optional) `http://localhost:3000` for mock API callback tests
   - **Authorized redirect URIs** — must match **exactly** what the app sends (including `localhost` vs `127.0.0.1`). The PoC uses the **same** callback path as Keycloak (`/oauth/callback`). Add **every** variant you use:
     - `http://localhost:5173/oauth/callback`
     - `http://127.0.0.1:5173/oauth/callback`
     - (optional) `http://localhost:3000/callback/google` if you point `VITE_OAUTH_REDIRECT_URI` there
   - If you see **`Error 400: redirect_uri_mismatch`**, check the `redirect_uri` query param on the request to `accounts.google.com`. The PoC maps IPv6 loopback (`::1`) to `http://localhost:<port>` in dev — if your port is not **5173**, add that port explicitly in the Console.
   - Old PoC URIs under `/google/callback` still work: the dev server redirects that path to `/oauth/callback` with the same query string (you should still register `/oauth/callback` in Google Cloud).
4. Click **Create**
5. Copy **Client ID** and **Client Secret**

---

## Step 5: Add Credentials to PoC

### Vue PoC (`poc/ts-vue`)

Copy `poc/ts-vue/.env.example` to `.env` and set:

```bash
VITE_GOOGLE_CLIENT_ID=your-id.apps.googleusercontent.com
VITE_GOOGLE_CLIENT_SECRET=GOCSPX-...
```

Restart `npm run dev`. Without both values, the UI keeps Google actions disabled (avoids Google’s “Missing required parameter: client_id” error).

### SDK init (generic)

You can also pass the same values via `MorphOptions.variables`:

```typescript
variables: {
  googleClientId: 'YOUR_GOOGLE_CLIENT_ID',
  googleClientSecret: 'YOUR_GOOGLE_CLIENT_SECRET',
  oauthCallbackUri: 'http://localhost:5173/oauth/callback',
}
```

---

## Step 6: Verify the Setup

### Generate PKCE challenge

```bash
CODE_VERIFIER=$(openssl rand -base64 32 | tr -d '=/+' | head -c 43)
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | openssl base64 | tr -d '=' | tr '/+' '_-')
echo "verifier:  $CODE_VERIFIER"
echo "challenge: $CODE_CHALLENGE"
```

### Open authorization URL

Replace `CLIENT_ID` and `CODE_CHALLENGE`:

```
https://accounts.google.com/o/oauth2/v2/auth?response_type=code&client_id=CLIENT_ID&redirect_uri=http://localhost:3000/callback/google&scope=openid%20profile%20email&access_type=offline&code_challenge_method=S256&code_challenge=CODE_CHALLENGE&prompt=consent
```

### Exchange code for tokens

After redirect to `http://localhost:3000/callback/google?code=AUTH_CODE`:

```bash
curl -X POST https://oauth2.googleapis.com/token \
  -d "grant_type=authorization_code" \
  -d "code=AUTH_CODE" \
  -d "client_id=CLIENT_ID" \
  -d "client_secret=CLIENT_SECRET" \
  -d "redirect_uri=http://localhost:3000/callback/google" \
  -d "code_verifier=CODE_VERIFIER"
```

### Test userinfo

```bash
curl -H "Authorization: Bearer ACCESS_TOKEN" \
  https://www.googleapis.com/oauth2/v3/userinfo
```

### Test mock API with Google token

```bash
curl -H "Authorization: Bearer ACCESS_TOKEN" \
  http://localhost:3000/identity/verify
```

---

## Endpoints Reference

| SDK Config Field | Google Endpoint |
|---|---|
| `provider.baseUrl` | `https://accounts.google.com` |
| `authorization.endpoint` | `/o/oauth2/v2/auth` |
| `token.endpoint` | `https://oauth2.googleapis.com/token` (absolute, different domain) |
| `logout.endpoint` | N/A (session-based) |
| JWKS | `https://www.googleapis.com/oauth2/v3/certs` |
| Userinfo | `https://www.googleapis.com/oauth2/v3/userinfo` |

**Note**: Google's token endpoint is on a different domain than the authorization endpoint. The SDK supports absolute endpoint URLs that override the provider's `baseUrl`.
