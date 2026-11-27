#!/usr/bin/env bash
set -euo pipefail

deploy_script="${CNR_DEPLOY_SCRIPT:-}"
if [[ -z "$deploy_script" ]]; then
  printf '%s\n' 'Set CNR_DEPLOY_SCRIPT to the path of your deployment executable.' >&2
  exit 1
fi

if [[ "$deploy_script" != /* ]]; then
  deploy_script="$PWD/$deploy_script"
fi
if [[ ! -f "$deploy_script" || ! -x "$deploy_script" ]]; then
  printf 'CNR_DEPLOY_SCRIPT must point to an executable file: %s\n' "$deploy_script" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
exec "$deploy_script" "$root/dist/Client/CopsAndRobbers.zip" "$root/dist/Server/CopsAndRobbers"
