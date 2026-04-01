# YiJv www

Static site for https://www.yijvyijv.site.

## Files
- `index.html`
- `privacy.html`
- `deploy-www-site.sh`

## Deployment Overview

This repository is published to GitHub and deployed from the server by pulling the
latest Git commits. The deploy script connects to the server, updates the checked
out branch in the server-side repo, syncs the static files into the Nginx site
directory, and reloads Nginx.

Default paths and values used by `deploy-www-site.sh`:

- server SSH host: `yijv-server`
- repo dir on server: `/home/ubuntu/repos/YiJv-www`
- deploy branch: `main`
- site dir served by Nginx: `/var/www/yijv_www`
- apex domain: `yijvyijv.site`
- www domain: `www.yijvyijv.site`

## Server Setup

Prepare the server once before the first deploy:

```bash
mkdir -p /home/ubuntu/repos
cd /home/ubuntu/repos
git clone git@github.com:bjmark/yijv-www.git YiJv-www
```

Make sure the server can access the GitHub repository over SSH and has these
dependencies installed:

- `git`
- `rsync`
- `nginx`

The deploy script also expects TLS certificates to exist under:

```bash
/etc/letsencrypt/live/yijvyijv.site
```

## Daily Deploy

Push your local changes to GitHub:

```bash
git push origin main
```

Then run the deploy script from this repository root:

```bash
./deploy-www-site.sh
```

## Optional Environment Variables

You can override the defaults when needed:

```bash
YIJV_SERVER_HOST=yijv-server \
YIJV_APEX_DOMAIN=yijvyijv.site \
YIJV_WWW_DOMAIN=www.yijvyijv.site \
YIJV_HTTPS_UPSTREAM_PORT=3000 \
REPO_DIR=/home/ubuntu/repos/YiJv-www \
BRANCH=main \
REMOTE_SITE_DIR=/var/www/yijv_www \
./deploy-www-site.sh
```
