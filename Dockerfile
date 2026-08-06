# Stage 1: Dependencies
# Node 22+ is required: corepack installs pnpm@latest (11.x), which depends
# on the builtin node:sqlite module, only available since Node 22.13.
FROM node:22-alpine AS deps
RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

# Stage 2: Builder
FROM node:22-alpine AS builder
RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build arguments for environment variables needed at build time
ARG WORDPRESS_URL
ARG WORDPRESS_HOSTNAME
ENV WORDPRESS_URL=$WORDPRESS_URL
ENV WORDPRESS_HOSTNAME=$WORDPRESS_HOSTNAME
ENV NEXT_TELEMETRY_DISABLED=1

RUN pnpm build

# Stage 3: Runner
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

# Railway sets PORT dynamically - default to 3000 if not set
ENV HOSTNAME="0.0.0.0"

CMD ["node", "server.js"]
