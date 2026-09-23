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

mkdir -p "${DATA_DIR:-/app/data/9router}"
mkdir -p "$(dirname "${DB_PATH:-/app/data/panel.db}")"

cleanup() {
    log "Shutting down all services..."
    pkill -TERM -f "node.*9router" 2>/dev/null || true
    pkill -TERM -f "mtg" 2>/dev/null || true
    pkill -TERM -f "server.js" 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

pkill -9 -f "9router" 2>/dev/null || true
pkill -9 -f "node.*20128" 2>/dev/null || true
pkill -9 -f "mtg" 2>/dev/null || true
sleep 1

# ---------- متغیرهای 9Router ----------
if [ -z "${INITIAL_PASSWORD:-}" ]; then
    INITIAL_PASSWORD="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
fi
export INITIAL_PASSWORD

if [ -z "${JWT_SECRET:-}" ]; then
    JWT_SECRET="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"
fi
export JWT_SECRET

PORT_9ROUTER="${PORT_9ROUTER:-20128}"
PORT_MTPROTO="${PORT_MTPROTO:-3128}"

# ---------- ساخت سکرت ضد فیلتر FakeTLS تلگرام ----------
# استفاده از دامین معتبر کلودفلر برای دور زدن فیلترینگ
TLS_DOMAIN="cloudflare.com"
if [ -z "${MTPROTO_SECRET:-}" ]; then
    MTPROTO_SECRET=$(mtg generate-secret --hex "$TLS_DOMAIN")
fi

# ---------- استارت پروکسی تلگرام (MTG) ----------
log "Starting Telegram MTProto Proxy on port ${PORT_MTPROTO}..."
mtg run -b "0.0.0.0:${PORT_MTPROTO}" "$MTPROTO_SECRET" > /tmp/mtg.log 2>&1 &
MTG_PID=$!

# بررسی وضعیت TCP Proxy ریلوِی برای لینک تلگرام
TCP_HOST="${RAILWAY_TCP_PROXY_DOMAIN:-}"
TCP_PORT="${RAILWAY_TCP_PROXY_PORT:-}"

echo ""
echo "=================================================="
echo "  🚀 ALL-IN-ONE SERVICES READY"
echo "=================================================="
echo "  🖥️  Panel Port:     ${PORT:-8080}"
echo "  🔑 9Router Port:   ${PORT_9ROUTER}"
echo "     9Router Pass:   ${INITIAL_PASSWORD}"
echo "--------------------------------------------------"
if [ -n "$TCP_HOST" ] && [ -n "$TCP_PORT" ]; then
    echo "  ✈️ TELEGRAM PROXY LINK:"
    echo "  tg://proxy?server=${TCP_HOST}&port=${TCP_PORT}&secret=${MTPROTO_SECRET}"
    echo "  https://t.me/proxy?server=${TCP_HOST}&port=${TCP_PORT}&secret=${MTPROTO_SECRET}"
else
    echo "  ✈️ Telegram Proxy internal: 0.0.0.0:${PORT_MTPROTO}"
    echo "  ⚠️ TCP Proxy is not enabled yet in Railway Settings!"
    echo "  Secret: ${MTPROTO_SECRET}"
fi
echo "=================================================="
echo ""

# ---------- استارت سرور مستقل 9Router ----------
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

# ---------- استارت پنل اصلی ----------
log "Starting LM-Panel on port ${PORT:-8080}..."
cd /app || exit 1
exec node server.js
