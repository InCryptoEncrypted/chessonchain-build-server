# chessonchain-build-server

Turn any VPS into a **staging + production** build server: pull → Docker → GHCR → Coolify.

## 3-step setup

### 1. On your laptop (chessonchain repo)

```bash
cd chessonchain
node scripts/export-github-secrets-from-coolify.mjs staging
node scripts/export-github-secrets-from-coolify.mjs production   # if prod app is running
node scripts/export-buildserver-env.mjs
```

Edit `.ci-secrets/buildserver.env` — set `GITHUB_TOKEN` and `WEBHOOK_SECRET` (`openssl rand -hex 32`).

### 2. On the build VPS

```bash
git clone https://github.com/InCryptoEncrypted/chessonchain-build-server.git /opt/build-server
scp .ci-secrets/buildserver.env root@YOUR_VPS:/opt/build-server/.env
ssh root@YOUR_VPS
sudo /opt/build-server/scripts/install.sh
sudo ufw allow 9876/tcp
```

### 3. GitHub webhook (chessonchain repo)

**Settings → Webhooks → Add webhook**

| Field | Value |
|-------|--------|
| URL | `http://YOUR_VPS_IP:9876/github` |
| Secret | `WEBHOOK_SECRET` from `.env` |
| Events | Push |

Pushes to `develop` → **staging**. Pushes to `stable-master-01` → **production**.

## Manual deploy

```bash
/opt/build-server/scripts/deploy.sh staging
/opt/build-server/scripts/deploy.sh production
```

## Logs

```bash
journalctl -u chessonchain-build-webhook -f
```

## Env file format

One `.env` with prefixed secrets:

- `STAGING_*` — build vars for develop / staging.chessonchain.io
- `PRODUCTION_*` — build vars for stable-master-01 / play.chessonchain.io
- Global: `GITHUB_TOKEN`, `COOLIFY_TOKEN`, `WEBHOOK_*`

See `buildserver.env.example`.
