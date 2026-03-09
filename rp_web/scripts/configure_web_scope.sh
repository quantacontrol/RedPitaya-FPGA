#!/bin/bash

# Script to configure the rp-web-scope decimation and settings via API
# Usage: ./configure_web_scope.sh [decimation] [trigger_level]

DECIMATION=${1:-8192}
TRIGGER_LEVEL=${2:-0.0}
TRIGGER_SOURCE=0 # Auto

API_URL="http://localhost:3000/api/v1/scope/config"

echo "Configuring Web Scope..."
echo "Decimation: $DECIMATION"
echo "Trigger Level: $TRIGGER_LEVEL"

# JSON payload
PAYLOAD=$(cat <<EOF
{
  "decimation": $DECIMATION,
  "trigger_level": $TRIGGER_LEVEL,
  "trigger_source": $TRIGGER_SOURCE
}
EOF
)

# Send request
curl -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$API_URL"

echo ""
echo "Done. Please refresh the web interface or wait for the next poll."
echo "If decimation is 8192, 16k samples covers ~1 second."
