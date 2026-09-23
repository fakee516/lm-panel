#!/bin/bash
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; }

# ساخت پوشه‌های دیتابیس
mkdir -p "${DATA_DIR:-/app/data/9router}"
mkdir -p "$(dirname "${DB_PATH:-/app/data/panel.db}")"

cleanup() {
    log "Shutting down..."
    pkill -TERM -f "node.*9router" 2>/dev/null || true
    pkill -TERM -f "server.js" 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

log "==============================================="
log "  LM-Panel + 9Router — Starting up"
log "==============================================="

# پاکسازی پروسه‌های قبلی
pkill -9 -f "9router" 2>/dev/null || true
pkill -9 -f "node.*20128" 2>/dev/null || true
sleep 1

# پسورد و سکرت روتر
if [ -z "${INITIAL_PASSWORD:-}" ]; then
    INITIAL_PASSWORD="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
    warn "INITIAL_PASSWORD not set — generated: ${INITIAL_PASSWORD}"
fi
export INITIAL_PASSWORD

if [ -z "${JWT_SECRET:-}" ]; then
    JWT_SECRET="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"
    warn "JWT_SECRET not set — generated automatically."
fi
export JWT_SECRET

PORT_9ROUTER="${PORT_9ROUTER:-20128}"
export PORT_9ROUTER

echo ""
echo "=================================================="
echo "  🔑 9Router Dashboard"
echo "  Password: ${INITIAL_PASSWORD}"
echo "  JWT Secret: ${JWT_SECRET}"
echo "  Port:     ${PORT_9ROUTER}"
echo "=================================================="
echo "  🖥️  Panel (LM-Panel)"
echo "  Port:     ${PORT:-8080}"
echo "  DB:       ${DB_PATH:-/app/data/panel.db}"
echo "=================================================="
echo ""

# پیدا کردن مسیر واقعی سرور 9router در پکیج گلوبال npm
NINE_DIR="$(npm root -g)/9router/app"
if [ ! -d "$NINE_DIR" ]; then
    NINE_DIR="/usr/local/lib/node_modules/9router/app"
fi

RUN_SCRIPT="server.js"
if [ -f "$NINE_DIR/custom-server.js" ]; then
    RUN_SCRIPT="custom-server.js"
elif [ -f "$NINE_DIR/server.js" ]; then
    RUN_SCRIPT="server.js"
fi

log "Targeting 9Router server at: ${NINE_DIR}/${RUN_SCRIPT}"

# اجرای مستقیم سرور نود (بدون TUI و بدون پرسیدن منو)
(
    cd "$NINE_DIR" || exit 1
    export PORT="$PORT_9ROUTER"
    export HOSTNAME="0.0.0.0"
    export DATA_DIR="${DATA_DIR:-/app/data/9router}"
    export INITIAL_PASSWORD="${INITIAL_PASSWORD}"
    export JWT_SECRET="${JWT_SECRET}"
    export NODE_ENV="production"
    export NEXT_TELEMETRY_DISABLED=1
    exec node "$RUN_SCRIPT"
) > /tmp/9router.log 2>&1 &

NINE_PID=$!
log "9Router process spawned with PID ${NINE_PID}"

# بررسی واقعی باز شدن پورت با تست شبکه (تا حداکثر ۱۵ ثانیه)
log "Waiting for 9Router port ${PORT_9ROUTER} to respond..."
READY=false
for i in $(seq 1 15); do
    if curl -s -m 1 "http://127.0.0.1:${PORT_9ROUTER}/" > /dev/null 2>&1 || \
       curl -s -m 1 "http://127.0.0.1:${PORT_9ROUTER}/login" > /dev/null 2>&1; then
        READY=true
        break
    fi
    sleep 1
done

if [ "$READY" = true ]; then
    ok "9Router is UP and actively listening on port ${PORT_9ROUTER}!"
else
    warn "9Router health-check pending. Current logs:"
    cat /tmp/9router.log | tail -n 25 || true
fi

# اجرای پنل اصلی
log "Starting LM-Panel on port ${PORT:-8080}..."
cd /app || exit 1
exec node server.js
