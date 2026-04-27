#!/usr/bin/env bash
# One-time setup script for tv.awastats.com on a fresh Ubuntu/Debian server.
#
# Usage on the SERVER (not your laptop):
#   curl -fsSL https://raw.githubusercontent.com/YDX64/awatv/main/scripts/setup-server.sh | sudo bash
#
# What it does:
#   1. Installs nginx + certbot (Let's Encrypt)
#   2. Creates web root at /var/www/tv.awastats.com
#   3. Drops in nginx vhost for tv.awastats.com (PWA-friendly: long cache for /assets/, no-cache for index.html)
#   4. Issues TLS cert via certbot
#   5. Reloads nginx

set -euo pipefail

DOMAIN="${DOMAIN:-tv.awastats.com}"
EMAIL="${EMAIL:-yunusd64@gmail.com}"   # Let's Encrypt registration email
WEB_ROOT="/var/www/${DOMAIN}"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

bold "==> apt update + base packages"
apt-get update -qq
apt-get install -y nginx certbot python3-certbot-nginx rsync

bold "==> Web root at ${WEB_ROOT}"
mkdir -p "$WEB_ROOT"
chown -R www-data:www-data "$WEB_ROOT"
echo "<h1>${DOMAIN} placeholder</h1><p>Deploy via GitHub Actions or scripts/deploy-web.sh</p>" > "$WEB_ROOT/index.html"

bold "==> nginx vhost"
cat > "/etc/nginx/sites-available/${DOMAIN}" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    # Certbot will move this block to https-listening server after issuance.
    location / {
        return 301 https://\$host\$request_uri;
    }

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/_acme;
        try_files \$uri =404;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    # SSL — certbot fills these in
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    root ${WEB_ROOT};
    index index.html;

    # SPA fallback — Flutter web is a single-page app.
    location / {
        try_files \$uri \$uri/ /index.html;

        # Don't cache the entry point — it references hashed assets.
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        add_header Pragma "no-cache" always;
    }

    # Hashed assets — long cache (1 year, immutable)
    location /assets/ {
        access_log off;
        add_header Cache-Control "public, max-age=31536000, immutable" always;
    }
    location /canvaskit/ {
        access_log off;
        add_header Cache-Control "public, max-age=31536000, immutable" always;
    }
    location ~* \.(woff2?|ttf|otf)\$ {
        access_log off;
        add_header Cache-Control "public, max-age=31536000, immutable" always;
    }

    # Service worker — must NOT be cached aggressively, or PWA updates break.
    location = /flutter_service_worker.js {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
    }
    location = /flutter_bootstrap.js {
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
    }
    location = /manifest.json {
        add_header Cache-Control "no-cache, must-revalidate" always;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    # Permissive CSP to allow video sources from arbitrary IPTV providers + TMDB images.
    add_header Content-Security-Policy "default-src 'self'; img-src 'self' data: https: http:; media-src 'self' blob: https: http:; connect-src 'self' https: http: wss: ws:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'; font-src 'self' data:; manifest-src 'self'; worker-src 'self' blob:;" always;

    # Permission policy: allow PiP, fullscreen, autoplay
    add_header Permissions-Policy "fullscreen=(self), autoplay=(self), picture-in-picture=(self)" always;

    # Brotli/gzip — enable in /etc/nginx/nginx.conf
    gzip on;
    gzip_types text/plain text/css application/json application/javascript application/wasm image/svg+xml;
    gzip_min_length 1024;

    # Body size — generous for video posts (rare)
    client_max_body_size 25m;
}
NGINX

ln -sf "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/${DOMAIN}"
mkdir -p /var/www/_acme

bold "==> Issuing TLS certificate via certbot"
# Temporarily disable the https block until cert is issued.
sed -i.bak '/listen 443/,/^}/d' "/etc/nginx/sites-available/${DOMAIN}"
nginx -t
systemctl reload nginx

certbot certonly --webroot -w /var/www/_acme -d "${DOMAIN}" \
  --non-interactive --agree-tos --email "${EMAIL}" --no-eff-email

# Restore the full vhost
mv "/etc/nginx/sites-available/${DOMAIN}.bak" "/etc/nginx/sites-available/${DOMAIN}"
nginx -t
systemctl reload nginx

bold "==> Auto-renew via systemd timer (built-in to certbot package)"
systemctl enable --now certbot.timer

bold "==> ✅ Setup complete"
echo
echo "Next: deploy from your laptop"
echo "    DEPLOY_HOST=${DOMAIN} DEPLOY_USER=$(logname) DEPLOY_PATH=${WEB_ROOT} ./scripts/deploy-web.sh"
echo
echo "Or trigger GitHub Actions deploy-web workflow once secrets are set:"
echo "    gh secret set DEPLOY_HOST --body=${DOMAIN}"
echo "    gh secret set DEPLOY_USER --body=$(logname)"
echo "    gh secret set DEPLOY_PATH --body=${WEB_ROOT}"
echo "    gh secret set DEPLOY_SSH_KEY < ~/.ssh/id_ed25519"
