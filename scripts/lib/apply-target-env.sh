#!/usr/bin/env bash
# After sourcing .env: map STAGING_* / PRODUCTION_* → flat env for ci-build-env.mjs
# Usage: source scripts/lib/apply-target-env.sh staging|production
set -euo pipefail

_target="${1:?usage: apply-target-env.sh staging|production}"
_prefix="$(echo "$_target" | tr '[:lower:]' '[:upper:]')"

_branch_var="${_prefix}_BRANCH"
_webhook_var="${_prefix}_COOLIFY_DEPLOY_WEBHOOK"
_cache_var="${_prefix}_REPO_CACHE"

export BUILD_DEPLOY_TARGET="$_target"
export BUILD_BRANCH="${!_branch_var:?Set ${_branch_var} in .env}"
export COOLIFY_DEPLOY_WEBHOOK="${!_webhook_var:?Set ${_webhook_var} in .env}"
export BUILD_REPO_PATH="${!_cache_var:-${BUILD_REPO_CACHE_ROOT:-/var/cache/chessonchain-build}/${_target}}"

for key in $(compgen -e | grep "^${_prefix}_" || true); do
  bare="${key#${_prefix}_}"
  case "$bare" in
    BRANCH | COOLIFY_DEPLOY_WEBHOOK | REPO_CACHE) continue ;;
  esac
  # shellcheck disable=SC2163
  eval "export ${bare}=\"\${${key}}\""
done
