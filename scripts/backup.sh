#!/bin/bash
# Database backup script for Flashcards
# Usage: ./scripts/backup.sh [backup_dir]
# To schedule daily backups, add to crontab:
# 0 2 * * * /opt/flashcards/scripts/backup.sh >> /var/log/flashcards-backup.log 2>&1

set -e

BACKUP_DIR="${1:-/opt/flashcards/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/flashcards_${TIMESTAMP}.sql"
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

echo "Creating backup: $BACKUP_FILE"

docker compose exec -T db pg_dump -U flashcards flashcards > "$BACKUP_FILE"

gzip "$BACKUP_FILE"

echo "Backup created: ${BACKUP_FILE}.gz"

# Remove old backups
find "$BACKUP_DIR" -name "flashcards_*.sql.gz" -mtime +$RETENTION_DAYS -delete

echo "Cleanup complete (retention: ${RETENTION_DAYS} days)"
