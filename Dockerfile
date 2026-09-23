FROM node:20-slim

# 1. ابزارهای سیستمی و کامپایل
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

# 2. هسته Xray-Core
RUN set -eux; \
    wget -O /tmp/xray.zip \
        "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"; \
    unzip /tmp/xray.zip -d /usr/local/bin; \
    chmod +x /usr/local/bin/xray; \
    rm -f /tmp/xray.zip

# 3. باینری پروکسی MTG تلگرام
RUN set -eux; \
    MTG_VER=$(curl -sL https://api.github.com/repos/9seconds/mtg/releases/latest | grep tag_name | sed 's/.*"v\([^"]*\)".*/\1/') && \
    wget -O /tmp/mtg.tar.gz "https://github.com/9seconds/mtg/releases/download/v${MTG_VER}/mtg-${MTG_VER}-linux-amd64.tar.gz" && \
    tar -xzf /tmp/mtg.tar.gz -C /tmp && \
    mv /tmp/mtg-*/mtg /usr/local/bin/mtg && \
    chmod +x /usr/local/bin/mtg && \
    rm -rf /tmp/mtg*

# 4. روتر ۹
RUN npm install -g 9router --include=optional \
    && npm cache clean --force

WORKDIR /app

# 5. پکیج‌های پنل V2Ray
COPY package*.json ./
RUN npm install --omit=dev \
    && npm cache clean --force

COPY . .

# 6. ساخت پوشه دیتابیس پایدار
RUN mkdir -p /app/data/9router && chmod -R 755 /app/data

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 20128 3128

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/start.sh"]
