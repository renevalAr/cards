#!/bin/bash
# Healthcheck script for monitoring
# Usage: ./scripts/healthcheck.sh [base_url]

set -e

BASE_URL="${1:-http://localhost}"
HEALTH_URL="${BASE_URL}/api/health"

response=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null)

if [ "$response" = "200" ]; then
  echo "OK: Application is healthy (HTTP $response)"
  exit 0
else
  echo "FAIL: Application is unhealthy (HTTP $response)"
  exit 1
fi
