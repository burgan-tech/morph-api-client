# Morph Flutter PoC

Flutter sample app for the `morph-api-client` Dart SDK. Mirrors the
[TypeScript Vue PoC](../ts-vue) against the same Keycloak + mock-API backend.

## Prerequisites

The same backend stack as the TS PoC is required:

1. **Keycloak** (port 8080)

   ```bash
   cd ../keycloak
   docker compose up -d
   # First time only:
   ./setup.sh
   ```

2. **Mock API** (port 3000)

   ```bash
   cd ../mock-api
   npm install
   npm start
   ```

3. **Flutter SDK** ≥ 3.x (Dart ≥ 3.6)

## Run

```bash
cd poc/flutter-poc
flutter pub get
flutter run
```

Override client secrets (default values match the imported Keycloak realm):

```bash
flutter run \
  --dart-define=DEVICE_CLIENT_SECRET=morph-device-secret \
  --dart-define=LOGIN_CLIENT_SECRET=morph-login-secret \
  --dart-define=SESSION_CLIENT_SECRET=morph-session-secret
```

## Features (parity with TS PoC)

| Feature | TS Vue | Flutter |
|---------|--------|---------|
| Token status cards | ✅ | ✅ |
| Acquire device token | ✅ | ✅ |
| Login (2fa — browser OAuth) | ✅ | ✅ |
| Token exchange (2fa → 1fa) | ✅ | ✅ |
| Logout | ✅ | ✅ |
| Mock API call (GET /ping) | ✅ | ✅ |
| HTTP trace log | ✅ | ✅ |
| JWT claims bottom sheet | ✅ | ✅ |
| Google OAuth | optional | not wired |
| Persistent token storage | browser-storage | in-memory (PoC) |

## OAuth login flow

1. Tap **Login (2fa)** → app builds the Keycloak authorize URL via
   `MorphRuntime.getAuthorizationUrl` and opens it in the system browser
   using `url_launcher`.
2. User authenticates on Keycloak; Keycloak redirects to
   `morphpoc://oauth/callback?code=…&state=…`.
3. `app_links` delivers the URI to the app.
4. `MorphRuntime.completeOAuthCallback` exchanges the code for tokens.
5. The home screen refreshes token status; a snack-bar shows the result.

### Platform deep-link registration

| Platform | Config |
|----------|--------|
| Android | `android:scheme="morphpoc"` intent-filter in `AndroidManifest.xml` |
| iOS | `CFBundleURLSchemes: [morphpoc]` in `Info.plist` |

The redirect URI `morphpoc://oauth/callback` must be registered in
Keycloak → client → Valid Redirect URIs.

### Android emulator networking

On Android emulators `localhost` resolves to the emulator's own loopback
interface, not the host machine. The app detects `Platform.isAndroid` and
automatically substitutes `10.0.2.2` for all backend URLs (Keycloak,
mock-API). On physical devices and iOS simulators, `localhost` is used as-is.

## Architecture

```
lib/
  morph_init.dart      MorphClient singleton (mirrors poc/ts-vue/src/morph.ts)
  main.dart            MaterialApp + app_links deep-link listener
  screens/
    home_screen.dart   Token status, actions, mock API, HTTP trace
  widgets/
    token_status_card.dart   Per-authId status card + JWT claims sheet
    http_trace_log.dart      Expandable MorphHttpTraceEvent log
```

SDK packages consumed (all `path:` deps from `packages/dart/`):

- `morph_core` — `MorphClient`, `MorphRuntime`, `HostPipeline`
- `morph_oauth2` — `oauth2Plugin`, `TokenLifecycle`
- `morph_logger` — `loggerPlugin`
- `morph_storage` — `memoryStoragePlugin` (in-memory, PoC only)

## Token storage note

The PoC uses `morph_storage`'s in-memory provider; tokens are lost on
app restart. Persistent storage via `morph-data-store` is tracked
separately and will replace this in a future milestone.
