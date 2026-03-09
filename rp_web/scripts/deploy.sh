#!/bin/bash
set -e

TARGET=armv7-unknown-linux-gnueabihf
DEPLOY_DIR=deploy
RP_HOST=${RP_HOST:-rp-f0edec.local}
RP_USER=${RP_USER:-root}
RP_PASS=${RP_PASS:-root}

export RP_HOST
export RP_USER
export RP_PASS

echo "=== Building Red Pitaya Web Scope for ARM ==="

cd "$(dirname "$0")/.."

# Build backend for ARM
echo "Cross-compiling backend..."
cd backend
cross build --release --target $TARGET
cd ..

echo "Creating deployment package..."
rm -rf $DEPLOY_DIR
mkdir -p $DEPLOY_DIR/frontend

cp target/$TARGET/release/backend $DEPLOY_DIR/rp-web-scope

# Build frontend
echo "Building frontend..."
cd frontend
npm run build
cd ..

# Copy frontend
cp -r frontend/dist $DEPLOY_DIR/frontend/

# Create systemd service file
cat > $DEPLOY_DIR/rp-web-scope.service << 'EOF'
[Unit]
Description=Red Pitaya Web Scope
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/rp-web-scope
Environment=FRONTEND_PATH=/opt/rp-web-scope/frontend/dist
ExecStart=/opt/rp-web-scope/rp-web-scope
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo ""
echo "=== Build complete! ==="
echo "Deployment package created in: $DEPLOY_DIR/"
echo ""
echo "=== Deploying to Device ==="
.venv/bin/python scripts/deploy_to_device.py
