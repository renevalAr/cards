#!/bin/bash
# Database restore script for Flashcards
# Usage: ./scripts/restore.sh <backup_file>

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <backup_file>"
  echo "Example: $0 /opt/flashcards/backups/flashcards_20260901_020000.sql.gz"
  exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "Error: Backup file not found: $BACKUP_FILE"
  exit 1
fi

echo "Stopping backend container..."
cd /opt/flashcards
docker compose stop backend

echo "Restoring database from: $BACKUP_FILE"
gunzip -c "$BACKUP_FILE" | docker compose exec -T db pg_restore -U flashcards -d flashcards --clean --if-exists

echo "Starting backend container..."
docker compose start backend

echo "Restore complete: $BACKUP_FILE"
