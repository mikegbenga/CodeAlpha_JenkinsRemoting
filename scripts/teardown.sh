#!/usr/bin/env bash
# Stop the lab. Pass --purge to also delete volumes (all Jenkins data and agent workspaces).
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--purge" ]; then
  docker compose --profile inbound --profile arm64 down -v
else
  docker compose --profile inbound --profile arm64 down
fi
