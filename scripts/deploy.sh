#!/usr/bin/env bash
# Pull app repo → write build env → docker buildx push → trigger Coolify.
# Usage: ./scripts/deploy.sh [staging|production]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${BUILD_SERVER_ENV:-$ROOT/.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

TARGET="${1:-${BUILD_DEPLOY_TARGET:-staging}}"
REPO_PATH="${BUILD_REPO_PATH:-$ROOT/.cache/app}"
BRANCH="${BUILD_BRANCH:-develop}"
REPO_URL="${BUILD_REPO_URL:-}"
IMAGE="${BUILD_IMAGE:?Set BUILD_IMAGE in .env}"
ENV_SCRIPT="${BUILD_ENV_SCRIPT:-scripts/ci-build-env.mjs}"
DOCKERFILE="${BUILD_DOCKERFILE:-Dockerfile}"
PLATFORM="${BUILD_PLATFORM:-linux/amd64}"

: "${GITHUB_TOKEN:?Set GITHUB_TOKEN in .env}"
: "${COOLIFY_DEPLOY_WEBHOOK:?Set COOLIFY_DEPLOY_WEBHOOK in .env}"
: "${COOLIFY_TOKEN:?Set COOLIFY_TOKEN in .env}"
: "${REPO_URL:?Set BUILD_REPO_URL in .env (app source — cloned automatically)}"

mkdir -p "$(dirname "$REPO_PATH")"

if [[ ! -d "$REPO_PATH/.git" ]]; then
  echo "==> clone app → $REPO_PATH"
  # Token in URL for private repos (not echoed)
  clone_url="$REPO_URL"
  if [[ "$REPO_URL" == https://github.com/* ]]; then
    clone_url="https://x-access-token:${GITHUB_TOKEN}@${REPO_URL#https://}"
  fi
  git clone --branch "$BRANCH" --single-branch "$clone_url" "$REPO_PATH"
else
  cd "$REPO_PATH"
  echo "==> fetch $BRANCH @ $REPO_PATH"
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git pull --ff-only origin "$BRANCH"
fi

cd "$REPO_PATH"

if [[ -f "$ENV_SCRIPT" ]]; then
  echo "==> write build env ($ENV_SCRIPT)"
  node "$ENV_SCRIPT"
else
  echo "==> skip build env (no $ENV_SCRIPT)"
fi

TAG_SUFFIX="staging"
if [[ "$TARGET" == "production" ]]; then
  TAG_SUFFIX="latest"
fi

SHA="$(git rev-parse HEAD)"
echo "==> docker build + push ($IMAGE:$TAG_SUFFIX, sha-$SHA)"

echo "$GITHUB_TOKEN" | docker login ghcr.io -u "${GITHUB_ACTOR:-incryptoencrypted}" --password-stdin

docker buildx build \
  --platform "$PLATFORM" \
  -f "$DOCKERFILE" \
  -t "$IMAGE:$TAG_SUFFIX" \
  -t "$IMAGE:sha-$SHA" \
  --push \
  .

echo "==> trigger Coolify"
http_code="$(curl -sS -o /tmp/coolify-redeploy.json -w "%{http_code}" -X GET "$COOLIFY_DEPLOY_WEBHOOK" \
  -H "Authorization: Bearer ${COOLIFY_TOKEN}")"
echo "Coolify HTTP $http_code"
cat /tmp/coolify-redeploy.json 2>/dev/null || true
if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  echo "Coolify redeploy failed (HTTP $http_code)" >&2
  exit 1
fi

echo "==> done ($TARGET @ $SHA)"
