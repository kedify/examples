FROM cgr.dev/chainguard/node:latest AS base

FROM base AS deps

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM base AS builder
WORKDIR /app
COPY --chown=node:node --from=deps /app/node_modules ./node_modules
COPY --chown=node:node . .
# COPY .env.production .env.production
RUN npm run build
CMD ["/usr/bin/npm", "run", "dev"]

# FROM base AS runner
# WORKDIR /app

# ENV NODE_ENV=development

# COPY --from=builder --chown=node:node /app/public ./public
# COPY --from=builder --chown=node:node /app/.next/standalone ./
# COPY --from=builder --chown=node:node /app/.next/static ./.next/static

EXPOSE 3000

# CMD ["server.js"]

