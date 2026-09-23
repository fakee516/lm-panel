# ============================================================
#  LM-Panel + 9Router - All-in-One Dockerfile
#  Base: Node.js 20 (9Router requires Node 20+)
# ============================================================
FROM node:20-slim

# ---------- 1. System dependencies ----------
# - wget/unzip/curl: for Xray-Core download
# - python3/make/g++: for native modules (better-sqlite3)
# - procps/psmisc: for ps/pkill in start.sh
# - ca-certificates: for HTTPS downloads
# - tini: proper PID 1 signal handling
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        unzip \
        curl \
        python3 \
        make \
        g++ \
        procps \
        psmisc \
        ca-certificates \
        tini \
    && rm -rf /var/lib/apt/lists/*

# ---------- 2. Xray-Core (latest release) ----------
RUN set -eux; \
    wget -O /tmp/xray.zip \
        "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"; \
    unzip /tmp/xray.zip -d /usr/local/bin; \
    chmod +x /usr/local/bin/xray; \
    rm -f /tmp/xray.zip; \
    /usr/local/bin/xray version

# ---------- 3. 9Router (global install) ----------
# --include=optional is REQUIRED so the SQLite driver gets installed
RUN npm install -g 9router --include=optional \
    && npm cache clean --force

# ---------- 4. App setup ----------
WORKDIR /app

# Install panel dependencies first (better Docker layer caching)
COPY package*.json ./
RUN npm install --omit=dev \
    && npm cache clean --force

# Copy the rest of the panel source
COPY . .

# ---------- 5. Data directory (will be mounted as Volume) ----------
RUN mkdir -p /app/data/9router \
    && chmod -R 755 /app/data

# ---------- 6. Copy startup script ----------
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# ---------- 7. Environment defaults ----------
# Panel
ENV NODE_ENV=production
ENV DB_PATH=/app/data/panel.db

# 9Router
ENV DATA_DIR=/app/data/9router
ENV PORT_9ROUTER=20128
ENV HOSTNAME=0.0.0.0
ENV NINE_ROUTER_HOST=0.0.0.0
ENV NINE_ROUTER_PORT=20128

# ---------- 8. Expose ports (informational) ----------
EXPOSE 20128

# ---------- 9. Entrypoint with tini (proper signal handling) ----------
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/start.sh"]
