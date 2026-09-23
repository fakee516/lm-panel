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
    pkill -TERM -f "mtg" 2>/dev/null || true
    pkill -TERM -f "server.js" 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# پاکسازی پروسه‌های قدیمی
pkill -9 -f "9router" 2>/dev/null || true
pkill -9 -f "node.*20128" 2>/dev/null || true
pkill -9 -f "mtg" 2>/dev/null || true
sleep 1

PORT_9ROUTER="${PORT_9ROUTER:-20128}"
PORT_MTPROTO="${PORT_MTPROTO:-3128}"

# سکرت تلگرام (پیش‌فرض کلودفلر)
MTPROTO_SECRET="${MTPROTO_SECRET:-ee1603010200010001fc030386e24c3add636c6f7564666c6172652e636f6d}"

# ---------- ۱. استارت پروکسی تلگرام ----------
log "Starting Telegram MTProto Proxy on port ${PORT_MTPROTO}..."
nohup mtg simple-run --prefer-ip=prefer-ipv4 "0.0.0.0:${PORT_MTPROTO}" "$MTPROTO_SECRET" > /tmp/mtg.log 2>&1 &

TCP_HOST="${RAILWAY_TCP_PROXY_DOMAIN:-roundhouse.proxy.rlwy.net}"
TCP_PORT="${RAILWAY_TCP_PROXY_PORT:-13448}"

echo ""
echo "=================================================="
echo "  🚀 ALL-IN-ONE SERVICES DASHBOARD"
echo "=================================================="
echo "  🖥️  Panel Port:       ${PORT:-8080}"
echo "  🔑 9Router Port:     ${PORT_9ROUTER}"
echo "     9Router Pass:     ${INITIAL_PASSWORD:-Admin9Router@2026!}"
echo "--------------------------------------------------"
echo "  ✈️  TELEGRAM PROXY:"
echo "  tg://proxy?server=${TCP_HOST}&port=${TCP_PORT}&secret=${MTPROTO_SECRET}"
echo "  https://t.me/proxy?server=${TCP_HOST}&port=${TCP_PORT}&secret=${MTPROTO_SECRET}"
echo "=================================================="
echo ""

# ---------- ۲. استارت سرور مستقل روتر ۹ ----------
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
    export INITIAL_PASSWORD="${INITIAL_PASSWORD:-Admin9Router@2026!}"
    export JWT_SECRET="${JWT_SECRET:-f7b2a9e4d6c14829a3e508b17c2f6d90e8a71b3c5e4d2a6f8b0c9e7d5a3f1b2c}"
    export NODE_ENV="production"
    export NEXT_TELEMETRY_DISABLED=1
    exec node "$RUN_SCRIPT"
) > /tmp/9router.log 2>&1 &

# ---------- ۳. استارت پنل اصلی ----------
log "Starting LM-Panel on port ${PORT:-8080}..."
cd /app || exit 1
exec node server.js
