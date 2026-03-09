#!/bin/bash
echo "Starting Red Pitaya Web Scope (Development Mode)..."
echo "Open http://localhost:3000 in your browser."
echo ""
echo "Tip: Set RP_MOCK=1 to use mock data on non-Red Pitaya hardware."
echo "     Example: RP_MOCK=1 ./scripts/run_dev.sh"
echo ""

cd "$(dirname "$0")/.."
cd backend
exec cargo run
