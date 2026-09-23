# استفاده از Node.js 18 (مطابق ISSPanel)
FROM node:18-slim

# 1. نصب پیش‌نیازهای سیستمی
RUN apt-get update && apt-get install -y \
    wget unzip curl python3 make g++ procps psmisc \
    && rm -rf /var/lib/apt/lists/*

# 2. نصب Xray-Core (طبق Dockerfile اصلی ISSPanel)
RUN VERSION=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep tag_name | sed 's/.*"v\([^"]*\)".*/\1/') && \
    wget -O /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" && \
    unzip /tmp/xray.zip -d /usr/local/bin && \
    chmod +x /usr/local/bin/xray && \
    rm -rf /tmp/xray.zip

# 3. نصب سراسری 9Router با وابستگی‌های اختیاری (درایور SQLite)
RUN npm install -g 9router --include=optional

WORKDIR /app

# 4. نصب وابستگی‌های ISSPanel
COPY package*.json ./
RUN npm install

# 5. کپی بقیه کدها
COPY . .

# 6. کپی اسکریپت راه‌انداز
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# 7. متغیرهای محیطی 9Router
ENV DATA_DIR=/app/data/9router
ENV PORT_9ROUTER=20128
ENV HOSTNAME=0.0.0.0
ENV NODE_ENV=production

# 8. دستور اجرا
CMD ["/app/start.sh"]
