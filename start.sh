#!/bin/bash
# ============================================================
#  Startup script: runs 9Router + Panel in one container
# ============================================================
set -uo pipefail

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; }

# ---------- Ensure data dirs ----------
mkdir -p "${DATA_DIR:-/app/data/9router}"
mkdir -p "$(dirname "${DB_PATH:-/app/data/panel.db}")"

# ---------- Cleanup on exit ----------
cleanup() {
    log "Shutting down..."
    pkill -TERM -f "9router" 2>/dev/null || true
    sleep 1
    pkill -KILL -f "9router" 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

log "==============================================="
log "  LM-Panel + 9Router — Starting up"
log "==============================================="

# ---------- Kill leftover processes ----------
pkill -9 -f "9router" 2>/dev/null || true
sleep 1

# ---------- Resolve / generate 9Router password ----------
if [ -z "${INITIAL_PASSWORD:-}" ]; then
    INITIAL_PASSWORD="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
    warn "INITIAL_PASSWORD not set — generated a random one."
fi
export INITIAL_PASSWORD

# ---------- Resolve / generate JWT_SECRET ----------
if [ -z "${JWT_SECRET:-}" ]; then
    JWT_SECRET="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"
    warn "JWT_SECRET not set — generated a random one."
fi
export JWT_SECRET

# ---------- Show credentials in Deploy Logs ----------
echo ""
echo "=================================================="
echo "  🔑 9Router Dashboard"
echo "  URL:      (via reverse proxy domain)"
echo "  Password: ${INITIAL_PASSWORD}"
echo "  JWT:      ${JWT_SECRET}"
echo "  Internal: http://0.0.0.0:${PORT_9ROUTER:-20128}"
echo "=================================================="
echo ""
echo "  🖥️  Panel (LM-Panel)"
echo "  Port:     ${PORT:-3000}"
echo "  DB:       ${DB_PATH:-/app/data/panel.db}"
echo "=================================================="
echo ""

# ---------- Start 9Router in background ----------
log "Starting 9Router on port ${PORT_9ROUTER:-20128}..."
PORT="${PORT_9ROUTER:-20128}" \
HOSTNAME="0.0.0.0" \
DATA_DIR="${DATA_DIR:-/app/data/9router}" \
INITIAL_PASSWORD="${INITIAL_PASSWORD}" \
JWT_SECRET="${JWT_SECRET}" \
nohup 9router --host 0.0.0.0 --port "${PORT_9ROUTER:-20128}" \
    > /tmp/9router.log 2>&1 &

NINE_PID=$!
echo "${NINE_PID}" > /tmp/9router.pid
log "9Router started with PID ${NINE_PID}"

# ---------- Watchdog for 9Router ----------
(
    while true; do
        sleep 30
        if ! kill -0 "${NINE_PID}" 2>/dev/null; then
            err "9Router died. Restarting..."
            PORT="${PORT_9ROUTER:-20128}" \
            HOSTNAME="0.0.0.0" \
            DATA_DIR="${DATA_DIR:-/app/data/9router}" \
            INITIAL_PASSWORD="${INITIAL_PASSWORD}" \
            JWT_SECRET="${JWT_SECRET}" \
            nohup 9router --host 0.0.0.0 --port "${PORT_9ROUTER:-20128}" \
                >> /tmp/9router.log 2>&1 &
            NINE_PID=$!
            echo "${NINE_PID}" > /tmp/9router.pid
            log "9Router restarted with PID ${NINE_PID}"
        fi
    done
) &
WATCHDOG_PID=$!

# ---------- Wait for 9Router to boot ----------
sleep 3
if kill -0 "${NINE_PID}" 2>/dev/null; then
    ok "9Router is running."
    log "Last lines from 9Router log:"
    tail -n 10 /tmp/9router.log || true
else
    err "9Router failed to start! Check /tmp/9router.log"
    tail -n 30 /tmp/9router.log || true
fi

# ---------- Start Panel in foreground ----------
log "Starting LM-Panel on port ${PORT:-3000}..."
exec node server.js
