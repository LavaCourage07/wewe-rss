FROM node:20.16.0-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN npm i -g pnpm@8.15.4

FROM base AS build
ARG GLOBAL_CACHE_BUST="2025-08-26-02"
RUN echo "GLOBAL_CACHE_BUST=$GLOBAL_CACHE_BUST"
COPY . /usr/src/app
WORKDIR /usr/src/app


RUN pnpm install --frozen-lockfile

RUN pnpm run -r build

# Verify web build output exists (fail fast if not)
RUN test -f apps/web/dist/index.html && echo "Found apps/web/dist/index.html" || (echo "Missing apps/web/dist/index.html" && exit 1)
RUN ls -al apps/web/dist | cat

RUN pnpm deploy --filter=server --prod /app
RUN pnpm deploy --filter=server --prod /app-sqlite

## NOTE: we no longer copy web dist into /app here; we will copy in final stage to avoid cache issues

RUN cd /app && pnpm exec prisma generate

RUN cd /app-sqlite && \
    rm -rf ./prisma && \
    mv prisma-sqlite prisma && \
    pnpm exec prisma generate

FROM base AS app-sqlite
COPY --from=build /app-sqlite /app

WORKDIR /app

EXPOSE 4000

ENV NODE_ENV=production
ENV HOST="0.0.0.0"
ENV SERVER_ORIGIN_URL=""
ENV MAX_REQUEST_PER_MINUTE=60
ENV AUTH_CODE=""
ENV DATABASE_URL="file:../data/wewe-rss.db"
ENV DATABASE_TYPE="sqlite"

RUN chmod +x ./docker-bootstrap.sh

CMD ["./docker-bootstrap.sh"]


FROM base AS app
COPY --from=build /app /app

# Copy built web UI from build stage into final image explicitly and prepare hbs
COPY --from=build /usr/src/app/apps/web/dist /app/client
RUN [ -f /app/client/index.html ] && mv /app/client/index.html /app/client/index.hbs || true
RUN sed -i 's#/assets/#/dash/assets/#g' /app/client/index.hbs || true

WORKDIR /app

# list client to verify index.hbs exists in final image
RUN ls -al /app || true && ls -al /app/client || true

EXPOSE 4000

ENV NODE_ENV=production
ENV HOST="0.0.0.0"
ENV SERVER_ORIGIN_URL=""
ENV MAX_REQUEST_PER_MINUTE=60
ENV AUTH_CODE=""
ENV DATABASE_URL=""

RUN chmod +x ./docker-bootstrap.sh

CMD ["./docker-bootstrap.sh"]
