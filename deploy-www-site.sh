#!/usr/bin/env bash
set -euo pipefail

SERVER_HOST="${YIJV_SERVER_HOST:-yijv-server}"
APEX_DOMAIN="${YIJV_APEX_DOMAIN:-yijvyijv.site}"
WWW_DOMAIN="${YIJV_WWW_DOMAIN:-www.yijvyijv.site}"
UPSTREAM_PORT="${YIJV_HTTPS_UPSTREAM_PORT:-3000}"
LOCAL_SITE_DIR="${LOCAL_SITE_DIR:-.}"
REMOTE_SITE_DIR="${REMOTE_SITE_DIR:-/var/www/yijv_www}"
CERT_DIR="${CERT_DIR:-/etc/letsencrypt/live/${APEX_DOMAIN}}"

if [[ ! -f "${LOCAL_SITE_DIR}/index.html" ]]; then
  echo "missing ${LOCAL_SITE_DIR}/index.html" >&2
  exit 1
fi

TMP_TAR="$(mktemp)"
trap 'rm -f "${TMP_TAR}"' EXIT

tar -C "${LOCAL_SITE_DIR}" -cf "${TMP_TAR}" .
scp "${TMP_TAR}" "${SERVER_HOST}:/tmp/yijv_www_site.tar"

ssh "${SERVER_HOST}" \
  "REMOTE_SITE_DIR='${REMOTE_SITE_DIR}' APEX_DOMAIN='${APEX_DOMAIN}' WWW_DOMAIN='${WWW_DOMAIN}' UPSTREAM_PORT='${UPSTREAM_PORT}' CERT_DIR='${CERT_DIR}' bash -s" <<'EOS'
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

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
sudo tar -C "${REMOTE_SITE_DIR}" -xf /tmp/yijv_www_site.tar
sudo chown -R www-data:www-data "${REMOTE_SITE_DIR}"
rm -f /tmp/yijv_www_site.tar

sudo cp "${TMP_DIR}/www.conf" /etc/nginx/sites-available/yijv_www

if [[ -f /etc/nginx/sites-enabled/yijv_https ]]; then
  sudo rm -f /etc/nginx/sites-enabled/yijv_https
fi

sudo ln -sf /etc/nginx/sites-available/yijv_www /etc/nginx/sites-enabled/yijv_www
sudo nginx -t
sudo systemctl reload nginx

echo "[www-site] deployed to ${WWW_DOMAIN}"
EOS
