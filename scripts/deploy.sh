#!/usr/bin/env bash
# Pull app → build env → docker push GHCR → Coolify redeploy
# Usage: ./scripts/deploy.sh staging|production
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export BUILD_SERVER_ENV="${BUILD_SERVER_ENV:-$ROOT/.env}"

if [[ ! -f "$BUILD_SERVER_ENV" ]]; then
  echo "Missing $BUILD_SERVER_ENV — copy buildserver.env from your laptop." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$BUILD_SERVER_ENV"
set +a

TARGET="${1:?usage: deploy.sh staging|production}"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/apply-target-env.sh" "$TARGET"

REPO_URL="${BUILD_REPO_URL:?Set BUILD_REPO_URL}"
IMAGE="${BUILD_IMAGE:?Set BUILD_IMAGE}"
ENV_SCRIPT="${BUILD_ENV_SCRIPT:-scripts/ci-build-env.mjs}"
DOCKERFILE="${BUILD_DOCKERFILE:-Dockerfile}"
PLATFORM="${BUILD_PLATFORM:-linux/amd64}"

: "${GITHUB_TOKEN:?Set GITHUB_TOKEN}"
: "${COOLIFY_TOKEN:?Set COOLIFY_TOKEN}"

mkdir -p "$(dirname "$BUILD_REPO_PATH")"

if [[ ! -d "$BUILD_REPO_PATH/.git" ]]; then
  echo "==> clone $BUILD_BRANCH → $BUILD_REPO_PATH"
  clone_url="$REPO_URL"
  if [[ "$REPO_URL" == https://github.com/* ]]; then
    clone_url="https://x-access-token:${GITHUB_TOKEN}@${REPO_URL#https://}"
  fi
  git clone --branch "$BUILD_BRANCH" --single-branch "$clone_url" "$BUILD_REPO_PATH"
else
  cd "$BUILD_REPO_PATH"
  echo "==> pull $BUILD_BRANCH @ $BUILD_REPO_PATH"
  git fetch origin "$BUILD_BRANCH"
  git checkout "$BUILD_BRANCH"
  git pull --ff-only origin "$BUILD_BRANCH"
fi

cd "$BUILD_REPO_PATH"

if [[ -f "$ENV_SCRIPT" ]]; then
  echo "==> build env ($ENV_SCRIPT)"
  node "$ENV_SCRIPT"
else
  echo "==> skip build env (no $ENV_SCRIPT)"
fi

if [[ "$TARGET" == "production" ]]; then
  TAG_SUFFIX="latest"
  EXTRA_TAG="stable-master-01"
else
  TAG_SUFFIX="staging"
  EXTRA_TAG="develop"
fi

SHA="$(git rev-parse HEAD)"
echo "==> docker push $IMAGE:$TAG_SUFFIX (+ $EXTRA_TAG, sha-$SHA)"

echo "$GITHUB_TOKEN" | docker login ghcr.io -u "${GITHUB_ACTOR:-incryptoencrypted}" --password-stdin

docker buildx build \
  --platform "$PLATFORM" \
  -f "$DOCKERFILE" \
  -t "$IMAGE:$TAG_SUFFIX" \
  -t "$IMAGE:$EXTRA_TAG" \
  -t "$IMAGE:sha-$SHA" \
  --push \
  .

echo "==> Coolify ($TARGET)"
http_code="$(curl -sS -o /tmp/coolify-redeploy.json -w "%{http_code}" -X GET "$COOLIFY_DEPLOY_WEBHOOK" \
  -H "Authorization: Bearer ${COOLIFY_TOKEN}")"
echo "HTTP $http_code"
cat /tmp/coolify-redeploy.json 2>/dev/null || true
if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  echo "Coolify redeploy failed (HTTP $http_code)" >&2
  exit 1
fi

echo "==> done $TARGET @ $SHA"
