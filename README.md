# chessonchain-build-server

Minimal scripts to turn **any VPS** into a build server:

**git pull → build env → Docker push to GHCR → Coolify redeploy**

Works with [ChessOnChain](https://github.com/incryptoencrypted/chessonchain) or any app that has `Dockerfile` + `scripts/ci-build-env.mjs` (or similar).

## Quick start

### 1. Prepare the server (once)

```bash
curl -fsSL https://raw.githubusercontent.com/incryptoencrypted/chessonchain-build-server/main/scripts/install-prerequisites.sh | sudo bash
```

Or clone this repo and run `sudo ./scripts/install-prerequisites.sh`.

### 2. Clone **only** this repo

```bash
git clone https://github.com/incryptoencrypted/chessonchain-build-server.git /opt/build-server
```

The app (`chessonchain`) is cloned automatically on first deploy into `BUILD_REPO_PATH` — you do **not** need a separate chessonchain checkout.

### 3. Configure secrets

```bash
cp /opt/build-server/.env.example /opt/build-server/.env
chmod 600 /opt/build-server/.env
nano /opt/build-server/.env
```

Required:

| Variable | Description |
|----------|-------------|
| `BUILD_REPO_URL` | App git URL (e.g. `https://github.com/incryptoencrypted/chessonchain.git`) |
| `BUILD_REPO_PATH` | Where app is cloned/updated (cache dir, default `.cache/app`) |
| `BUILD_BRANCH` | Branch to deploy (`develop` = staging) |
| `BUILD_IMAGE` | GHCR image (`ghcr.io/incryptoencrypted/chessonchain`) |
| `GITHUB_TOKEN` | PAT with `write:packages` |
| `COOLIFY_*` | From Coolify app deploy webhook |
| App secrets | Same vars your app's `ci-build-env.mjs` expects |

### 4. Manual deploy

```bash
/opt/build-server/scripts/deploy.sh staging
```

Production:

```bash
BUILD_BRANCH=stable-master-01 BUILD_DEPLOY_TARGET=production /opt/build-server/scripts/deploy.sh production
```

(Or set those in `.env`.)

### 5. Webhook setup (auto deploy on push)

**On the build server:**

```bash
# 1. Generate a secret and add to .env
openssl rand -hex 32
# → paste into WEBHOOK_SECRET= in /opt/build-server/.env

# 2. Open port (or use nginx/Caddy later)
ufw allow 9876/tcp

# 3. Test listener (foreground)
cd /opt/build-server && node scripts/webhook-listener.mjs
# Should print: [webhook] /github on :9876 (branch develop → staging)
```

**On GitHub** (repo: `incryptoencrypted/chessonchain`):

1. **Settings → Webhooks → Add webhook**
2. **Payload URL:** `http://YOUR_CONTABO_IP:9876/github`
3. **Content type:** `application/json`
4. **Secret:** exact value of `WEBHOOK_SECRET` from `.env`
5. **Which events:** Just the **push** event
6. **Active:** checked → Add webhook

**Test:** Push to `develop` → GitHub **Recent Deliveries** should show `202 deploy started`. On the server, `deploy.sh` runs (clone/pull → build → GHCR → Coolify).

**Keep it running (systemd):**

```bash
cp /opt/build-server/systemd/build-webhook.service.example /etc/systemd/system/build-webhook.service
nano /etc/systemd/system/build-webhook.service   # WorkingDirectory=/opt/build-server
systemctl daemon-reload
systemctl enable --now build-webhook
journalctl -u build-webhook -f
```

## What each script does

| Script | Purpose |
|--------|---------|
| `scripts/deploy.sh` | Pull, `ci-build-env`, `docker buildx --push`, Coolify curl |
| `scripts/webhook-listener.mjs` | GitHub push → `deploy.sh` |
| `scripts/install-prerequisites.sh` | Docker, Node 24, buildx |

## Adapting for another project

1. Set `BUILD_REPO_PATH` to your app clone.
2. Set `BUILD_ENV_SCRIPT` if not `scripts/ci-build-env.mjs`.
3. Fill `.env` with whatever keys your build script reads.
4. Set `BUILD_IMAGE` to your GHCR path.

No changes to this repo required.

## Security

- Never commit `.env`.
- Use a strong `WEBHOOK_SECRET`.
- Prefer HTTPS reverse proxy in front of the webhook port.
- Scope `GITHUB_TOKEN` to `write:packages` only.
