#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_web.sh — start all PoC backends and the Flutter web app on Chrome
#
# Usage:  ./run_web.sh [--no-keycloak] [--no-mock-api] [--debug]
#
# Ports:
#   8080  — Keycloak (Docker)
#   3000  — Mock API (Node)
#   4200  — Flutter web app (Chrome)
#
# By default runs in --profile mode (single bundled JS, loads in ~2s).
# Pass --debug for hot-reload at the cost of a 30-60s load on each page
# reload (596 separate JS files), which can cause the OAuth code to expire.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FLUTTER_PORT=4200

# --- flags ---
START_KEYCLOAK=true
START_MOCK_API=true
FLUTTER_MODE="--profile"
for arg in "$@"; do
  case "$arg" in
    --no-keycloak)  START_KEYCLOAK=false ;;
    --no-mock-api)  START_MOCK_API=false ;;
    --debug)        FLUTTER_MODE="" ;;
  esac
done

# --- cleanup on exit ---
MOCK_API_PID=""
cleanup() {
  echo ""
  echo "Shutting down..."
  [ -n "$MOCK_API_PID" ] && kill "$MOCK_API_PID" 2>/dev/null || true
  if $START_KEYCLOAK; then
    docker compose -f "$POC_DIR/keycloak/docker-compose.yml" stop 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# --- 1. Keycloak ---
if $START_KEYCLOAK; then
  echo "▶ Starting Keycloak..."
  if ! docker compose -f "$POC_DIR/keycloak/docker-compose.yml" up -d 2>&1; then
    echo "  ⚠ Docker not available — skipping Keycloak."
    echo "    Start OrbStack (or Docker Desktop) and re-run, or pass --no-keycloak."
    START_KEYCLOAK=false
  else
    echo -n "  Waiting for Keycloak to be ready"
    until curl -sf http://localhost:8080/realms/morph > /dev/null 2>&1; do
      echo -n "."
      sleep 2
    done
    echo " ready!"
  fi
else
  echo "⏭  Skipping Keycloak (--no-keycloak)"
fi

# --- 2. Mock API ---
if $START_MOCK_API; then
  MOCK_API_DIR="$POC_DIR/mock-api"
  if [ ! -d "$MOCK_API_DIR/node_modules" ]; then
    echo "▶ Installing mock-api dependencies..."
    npm install --prefix "$MOCK_API_DIR" --silent
  fi

  echo "▶ Starting Mock API on http://localhost:3000..."
  node "$MOCK_API_DIR/server.js" &
  MOCK_API_PID=$!
  sleep 1
  echo "  Mock API running (PID: $MOCK_API_PID)"
else
  echo "⏭  Skipping Mock API (--no-mock-api)"
fi

# --- 3. Flutter web ---
echo ""
echo "▶ Starting Flutter web app on http://localhost:$FLUTTER_PORT ..."
echo "  OAuth callback: http://localhost:$FLUTTER_PORT/"

cd "$SCRIPT_DIR"
if [ -n "$FLUTTER_MODE" ]; then
  echo "  Mode: profile (fast load, no hot-reload — use --debug for hot-reload)"
else
  echo "  Mode: debug (hot-reload enabled, but page reloads are slow ~30-60s)"
fi
echo ""

# shellcheck disable=SC2086
flutter run \
  $FLUTTER_MODE \
  --device-id chrome \
  --web-port "$FLUTTER_PORT" \
  --web-browser-flag "--disable-web-security" \
  --dart-define DEVICE_CLIENT_SECRET=morph-device-secret \
  --dart-define LOGIN_CLIENT_SECRET=morph-login-secret \
  --dart-define SESSION_CLIENT_SECRET=morph-session-secret
