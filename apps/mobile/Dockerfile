# AWAtv mobile — Flutter web build, served by nginx.
#
# Used by Coolify (or any container platform): point the build at the
# repo root and Coolify will resolve `dockerfile-location: apps/mobile/Dockerfile`.
# Multi-stage so the final image is just nginx:alpine + the static bundle.

# ----------------------------------------------------------------------------
# Stage 1 — Flutter build
# ----------------------------------------------------------------------------
FROM ghcr.io/cirruslabs/flutter:3.41.7 AS builder

# Build-time configuration. Coolify passes these via --build-arg when the
# env vars are flagged is_buildtime=true in the project settings. They
# are stamped into apps/mobile/.env so flutter_dotenv finds them at the
# *web runtime* (web's "runtime" is the browser, after the build).
ARG SUPABASE_URL=""
ARG SUPABASE_ANON_KEY=""
ARG WEB_PROXY_URL=""
ARG TMDB_API_KEY=""

# Coolify clones the repo at /app — match that.
WORKDIR /app
COPY . /app

# Stamp the .env file consumed by flutter_dotenv. flutter_dotenv reads
# this at *web runtime* (in the browser, after the build), so it must
# exist before `flutter build web`.
RUN printf 'SUPABASE_URL=%s\nSUPABASE_ANON_KEY=%s\nWEB_PROXY_URL=%s\nTMDB_API_KEY=%s\n' \
      "$SUPABASE_URL" "$SUPABASE_ANON_KEY" "$WEB_PROXY_URL" "$TMDB_API_KEY" \
    > apps/mobile/.env

RUN flutter pub get \
 && (cd packages/awatv_core && dart run build_runner build --delete-conflicting-outputs) \
 && (cd apps/mobile && dart run build_runner build --delete-conflicting-outputs) \
 && cd apps/mobile \
 && flutter build web \
      --release \
      --pwa-strategy=offline-first \
      --no-tree-shake-icons \
      --base-href=/

# ----------------------------------------------------------------------------
# Stage 2 — nginx static server
# ----------------------------------------------------------------------------
FROM nginx:1.27-alpine

# Strip nginx default conf and drop ours in.
RUN rm /etc/nginx/conf.d/default.conf
COPY apps/mobile/nginx.conf /etc/nginx/conf.d/awatv.conf

COPY --from=builder /app/apps/mobile/build/web /usr/share/nginx/html

# Coolify routes traffic at port 80 by default.
EXPOSE 80

# nginx already runs in foreground via the default ENTRYPOINT/CMD.
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -q -O - http://127.0.0.1/index.html | grep -q "AWAtv" || exit 1
