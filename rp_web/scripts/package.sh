#!/bin/bash
cd "$(dirname "$0")/.."
# Remove build artifacts
rm -rf backend/target
rm -rf frontend/node_modules

# Ensure scripts are executable
chmod +x scripts/run_dev.sh

# Zip it up
zip -r rp-web-scope.zip backend frontend scripts/run_dev.sh
echo "Packaged to rp-web-scope.zip"
