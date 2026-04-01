#!/usr/bin/env bash
set -euo pipefail

SERVER_HOST="${YIJV_SERVER_HOST:-yijv-server}"
APEX_DOMAIN="${YIJV_APEX_DOMAIN:-yijvyijv.site}"
WWW_DOMAIN="${YIJV_WWW_DOMAIN:-www.yijvyijv.site}"
UPSTREAM_PORT="${YIJV_HTTPS_UPSTREAM_PORT:-3000}"
REPO_DIR="${REPO_DIR:-/home/ubuntu/repos/YiJv-www}"
BRANCH="${BRANCH:-main}"
REMOTE_SITE_DIR="${REMOTE_SITE_DIR:-/var/www/yijv_www}"
CERT_DIR="${CERT_DIR:-/etc/letsencrypt/live/${APEX_DOMAIN}}"

ssh "${SERVER_HOST}" \
  "REPO_DIR='${REPO_DIR}' BRANCH='${BRANCH}' REMOTE_SITE_DIR='${REMOTE_SITE_DIR}' APEX_DOMAIN='${APEX_DOMAIN}' WWW_DOMAIN='${WWW_DOMAIN}' UPSTREAM_PORT='${UPSTREAM_PORT}' CERT_DIR='${CERT_DIR}' bash -s" <<'EOS'
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "missing git repo at ${REPO_DIR}" >&2
  exit 1
fi

cd "${REPO_DIR}"
git fetch origin
git checkout "${BRANCH}"
git pull --ff-only origin "${BRANCH}"

cat > "${TMP_DIR}/www.conf" <<NGINX
server {
  listen 80;
  listen [::]:80;
  server_name ${WWW_DOMAIN};

  root ${REMOTE_SITE_DIR};
  index index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }
}

server {
  listen 80;
  listen [::]:80;
  server_name ${APEX_DOMAIN};

  location / {
    proxy_pass http://127.0.0.1:${UPSTREAM_PORT};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 60s;
  }
}

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name ${WWW_DOMAIN};

  ssl_certificate ${CERT_DIR}/fullchain.pem;
  ssl_certificate_key ${CERT_DIR}/privkey.pem;
  include /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

  root ${REMOTE_SITE_DIR};
  index index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }
}

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name ${APEX_DOMAIN};

  ssl_certificate ${CERT_DIR}/fullchain.pem;
  ssl_certificate_key ${CERT_DIR}/privkey.pem;
  include /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

  location / {
    proxy_pass http://127.0.0.1:${UPSTREAM_PORT};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_read_timeout 60s;
  }
}
NGINX

if ! sudo test -f "${CERT_DIR}/fullchain.pem" || ! sudo test -f "${CERT_DIR}/privkey.pem"; then
  echo "missing cert files in ${CERT_DIR}" >&2
  exit 1
fi

sudo mkdir -p "${REMOTE_SITE_DIR}"
sudo rsync -av --delete \
  --exclude '.git' \
  --exclude '.gitignore' \
  "${REPO_DIR}/" "${REMOTE_SITE_DIR}/"
sudo chown -R www-data:www-data "${REMOTE_SITE_DIR}"

sudo cp "${TMP_DIR}/www.conf" /etc/nginx/sites-available/yijv_www

if [[ -f /etc/nginx/sites-enabled/yijv_https ]]; then
  sudo rm -f /etc/nginx/sites-enabled/yijv_https
fi

sudo ln -sf /etc/nginx/sites-available/yijv_www /etc/nginx/sites-enabled/yijv_www
sudo nginx -t
sudo systemctl reload nginx

echo "[www-site] deployed ${BRANCH} from ${REPO_DIR} to ${WWW_DOMAIN}"
EOS
