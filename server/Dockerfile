FROM oven/bun:1
RUN apt-get update && apt-get install -y --no-install-recommends luajit && rm -rf /var/lib/apt/lists/*
WORKDIR /app/server
COPY server/package.json server/bun.lock ./
RUN bun install --production
COPY server/ ./
COPY assets/bot/ /app/assets/bot/
ENV BOT_LUAJIT=luajit
CMD ["bun", "run", "src/index.ts"]
