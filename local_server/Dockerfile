FROM node:18-bullseye-slim

WORKDIR /app
ENV NODE_ENV=production

# sqlite3 may require native compilation depending on platform/node version
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
RUN npm ci --omit=dev

COPY server.js ./server.js
COPY server ./server
COPY public ./public

EXPOSE 3000
CMD ["node", "server.js"]
