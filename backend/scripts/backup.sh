#!/usr/bin/env bash
# Respaldo de Golazo en el VPS: base de datos (pg_dump) + fotos y comprobantes (volumen uploads).
# Uso (en el servidor):  bash /opt/golazo/backend/scripts/backup.sh
# Cron diario (3:15 a. m.):  15 3 * * * bash /opt/golazo/backend/scripts/backup.sh >> /var/log/golazo-backup.log 2>&1
#
# Variables opcionales:
#   BACKUP_DIR     carpeta de destino (por defecto /opt/golazo-backups)
#   KEEP_DAYS      días que se conservan los respaldos (por defecto 7)
#   BACKUP_REMOTE  copia fuera del servidor con rsync por SSH, p. ej. usuario@otro-servidor:/respaldos/golazo
#                  (si se deja vacío, el respaldo queda SOLO en este servidor: no protege contra perder el VPS)
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-/opt/golazo-backups}"
KEEP_DAYS="${KEEP_DAYS:-7}"
STAMP="$(date +%Y-%m-%d_%H%M)"
DEST="$BACKUP_DIR/$STAMP"

cd "$BACKEND_DIR"
umask 077
mkdir -p "$DEST"

# Si algo falla, no se deja un respaldo a medias que parezca bueno.
trap 'echo "ERROR: el respaldo falló, se borra $DEST" >&2; rm -rf "$DEST"' ERR

echo "[$(date -Is)] Respaldando base de datos..."
docker compose exec -T db pg_dump -U golazo -d golazo --no-owner | gzip -9 > "$DEST/db.sql.gz"

echo "[$(date -Is)] Respaldando fotos y comprobantes..."
docker compose exec -T api tar -C /app/storage -cz . > "$DEST/uploads.tgz"

# Comprobaciones básicas: archivos íntegros y con contenido.
gzip -t "$DEST/db.sql.gz"
gzip -t "$DEST/uploads.tgz"
[ "$(stat -c %s "$DEST/db.sql.gz")" -gt 1000 ] || { echo "ERROR: el dump de la base quedó vacío" >&2; false; }

echo "[$(date -Is)] Listo: $DEST ($(du -sh "$DEST" | cut -f1))"

# Copia fuera del servidor (recomendado).
if [ -n "${BACKUP_REMOTE:-}" ]; then
  echo "[$(date -Is)] Copiando a $BACKUP_REMOTE ..."
  rsync -a "$DEST" "$BACKUP_REMOTE/"
fi

# Rotación: borra respaldos más viejos que KEEP_DAYS.
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$KEEP_DAYS" -exec rm -rf {} +
trap - ERR
