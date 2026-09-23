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

# پورت‌های اختصاصی ثابت - هیچ سرویسی روی پورت دیگری نمی‌افتد
PANEL_PORT=8080
ROUTER_PORT=20128
TG_PORT=3128

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

# کشتن هر پروسه قبلی برای جلوگیری از EADDRINUSE
pkill -9 -f "9router" 2>/dev/null || true
pkill -9 -f "mtg" 2>/dev/null || true
pkill -9 -f "node" 2>/dev/null || true
sleep 1

# سکرت تلگرام
MTPROTO_SECRET="${MTPROTO_SECRET:-ee1603010200010001fc030386e24c3add636c6f7564666c6172652e636f6d}"

# ---------- ۱. استارت پروکسی تلگرام روی 3128 ----------
log "Starting Telegram MTProto Proxy on port ${TG_PORT}..."
nohup mtg simple-run --prefer-ip=prefer-ipv4 "0.0.0.0:${TG_PORT}" "$MTPROTO_SECRET" > /tmp/mtg.log 2>&1 &

TCP_HOST="${RAILWAY_TCP_PROXY_DOMAIN:-trolley.proxy.rlwy.net}"
TCP_PORT="${RAILWAY_TCP_PROXY_PORT:-32488}"

echo ""
echo "=================================================="
echo "  🚀 ALL-IN-ONE SERVICES DASHBOARD"
echo "=================================================="
echo "  🖥️  Panel Port:       ${PANEL_PORT}"
echo "  🔑 9Router Port:     ${ROUTER_PORT}"
echo "     9Router Pass:     ${INITIAL_PASSWORD:-75757575}"
echo "--------------------------------------------------"
echo "  ✈️  TELEGRAM PROXY:"
echo "  tg://proxy?server=${TCP_HOST}&port=${TCP_PORT}&secret=${MTPROTO_SECRET}"
echo "  https://t.me/proxy?server=${TCP_HOST}&port=${TCP_PORT}&secret=${MTPROTO_SECRET}"
echo "=================================================="
echo ""

# ---------- ۲. استارت سرور روتر ۹ روی 20128 ----------
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
    export PORT="$ROUTER_PORT"
    export HOSTNAME="0.0.0.0"
    export DATA_DIR="${DATA_DIR:-/app/data/9router}"
    export INITIAL_PASSWORD="${INITIAL_PASSWORD:-75757575}"
    export JWT_SECRET="${JWT_SECRET:-f7b2a9e4d6c14829a3e508b17c2f6d90e8a71b3c5e4d2a6f8b0c9e7d5a3f1b2c}"
    export NODE_ENV="production"
    export NEXT_TELEMETRY_DISABLED=1
    exec node "$RUN_SCRIPT"
) > /tmp/9router.log 2>&1 &

# ---------- ۳. استارت پنل اصلی روی 8080 (ثابت) ----------
log "Starting LM-Panel on dedicated port ${PANEL_PORT}..."
cd /app || exit 1
export PORT="$PANEL_PORT"
exec node server.js
