#!/usr/bin/env bash
# One-time setup on Ubuntu/Debian build server.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

apt-get update
apt-get install -y git curl ca-certificates

if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

if ! command -v node >/dev/null || [[ "$(node -p process.versions.node.split('.')[0])" -lt 20 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y nodejs
fi

docker buildx create --use --name build-runner 2>/dev/null || docker buildx use build-runner

echo ""
echo "Done. Next:"
echo "  1. git clone https://github.com/InCryptoEncrypted/chessonchain-build-server.git /opt/build-server"
echo "  2. cp /opt/build-server/.env.example /opt/build-server/.env && nano .env"
echo "  3. /opt/build-server/scripts/deploy.sh staging"
echo "  4. (optional) systemd + GitHub webhook for auto deploy on push"
