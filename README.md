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

### 2. Clone this repo + your app

```bash
git clone https://github.com/incryptoencrypted/chessonchain-build-server.git /opt/build-server
git clone https://github.com/incryptoencrypted/chessonchain.git /opt/chessonchain
cd /opt/chessonchain && git checkout develop
```

### 3. Configure secrets

```bash
cp /opt/build-server/.env.example /opt/build-server/.env
chmod 600 /opt/build-server/.env
nano /opt/build-server/.env
```

Required:

| Variable | Description |
|----------|-------------|
| `BUILD_REPO_PATH` | Path to cloned app (`/opt/chessonchain`) |
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

### 5. Auto-deploy on push (optional)

```bash
# In .env:
WEBHOOK_SECRET=$(openssl rand -hex 32)
WEBHOOK_PORT=9876

node /opt/build-server/scripts/webhook-listener.mjs
```

GitHub → repo **Settings → Webhooks**:

- URL: `http://YOUR_SERVER_IP:9876/github`
- Secret: same as `WEBHOOK_SECRET`
- Events: **Push**

Systemd (persistent):

```bash
cp /opt/build-server/systemd/build-webhook.service.example /etc/systemd/system/build-webhook.service
# Edit WorkingDirectory + paths
systemctl enable --now build-webhook
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
