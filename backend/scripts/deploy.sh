#!/usr/bin/env bash
# Actualiza Golazo en el VPS: baja el código, reconstruye, migra y reinicia el API.
# Uso (en el servidor):  bash /opt/golazo/backend/scripts/deploy.sh
set -euo pipefail

REPO_DIR="${REPO_DIR:-/opt/golazo}"

cd "$REPO_DIR"
git pull

cd backend
docker compose --profile tools build
docker compose run --rm migrate
docker compose up -d api

docker compose ps
echo "Listo. Revisa: curl -s https://golazo-app.duckdns.org/v1/health"
