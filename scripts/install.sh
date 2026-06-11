#!/usr/bin/env bash
# One-shot setup on the build VPS. Run after copying .env to this directory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run: sudo $0" >&2
  exit 1
fi

if [[ ! -f "$ROOT/.env" ]]; then
  echo "Missing $ROOT/.env" >&2
  echo "Copy buildserver.env from your laptop:" >&2
  echo "  scp .ci-secrets/buildserver.env root@SERVER:/opt/build-server/.env" >&2
  exit 1
fi

chmod 600 "$ROOT/.env"
chmod +x "$ROOT/scripts/"*.sh "$ROOT/scripts/lib/"*.sh 2>/dev/null || true

bash "$ROOT/scripts/install-prerequisites.sh"

UNIT=/etc/systemd/system/chessonchain-build-webhook.service
cat > "$UNIT" <<EOF
[Unit]
Description=ChessOnChain build webhook (staging + production)
After=network.target docker.service

[Service]
Type=simple
WorkingDirectory=$ROOT
Environment=BUILD_SERVER_ENV=$ROOT/.env
ExecStart=/usr/bin/node $ROOT/scripts/webhook-listener.mjs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now chessonchain-build-webhook

echo ""
echo "Installed. Status:"
systemctl status chessonchain-build-webhook --no-pager || true
echo ""
echo "Manual deploy:"
echo "  $ROOT/scripts/deploy.sh staging"
echo "  $ROOT/scripts/deploy.sh production"
echo ""
echo "Logs: journalctl -u chessonchain-build-webhook -f"
