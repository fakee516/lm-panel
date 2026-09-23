#!/bin/bash
set -e

echo "=== [Startup] Initializing services ==="

# ---------- 1. کشتن پروسه‌های قبلی (جلوگیری از EADDRINUSE) ----------
pkill -9 -f "9router" 2>/dev/null || true
pkill -9 -f "node server.js" 2>/dev/null || true
sleep 2

# ---------- 2. خواندن یا تولید رمز 9Router ----------
# اگر INITIAL_PASSWORD در Railway Variables تنظیم نشده باشد، یک رمز تصادفی می‌سازیم
if [ -z "$INITIAL_PASSWORD" ]; then
  export INITIAL_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20)
  echo "⚠️  INITIAL_PASSWORD not set. Generated random password: $INITIAL_PASSWORD"
else
  echo "✅ INITIAL_PASSWORD is set from Railway Variables."
fi

# ---------- 3. نمایش رمز در لاگ (برای دیدن در Deploy Logs) ----------
echo "========================================="
echo "🔑 9Router Dashboard Password: $INITIAL_PASSWORD"
echo "🌐 9Router internal port: ${PORT_9ROUTER:-20128}"
echo "========================================="

# ---------- 4. اجرای 9Router در پس‌زمینه ----------
echo "Starting 9Router on port ${PORT_9ROUTER:-20128}..."
# استفاده از PORT_9ROUTER برای جلوگیری از تداخل با $PORT اصلی Railway
PORT=${PORT_9ROUTER:-20128} \
HOSTNAME=0.0.0.0 \
DATA_DIR=${DATA_DIR:-/app/data/9router} \
INITIAL_PASSWORD="$INITIAL_PASSWORD" \
nohup 9router --host 0.0.0.0 --port ${PORT_9ROUTER:-20128} --no-browser --skip-update \
  > /tmp/9router.log 2>&1 &

# ---------- 5. اجرای ISSPanel در پیش‌زمینه ----------
echo "Starting ISSPanel on port $PORT..."
export DB_PATH=/app/data/isspanel.db
exec node server.js
