#!/bin/bash
# Setup test environment with Docker

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Setting up Docker test environment"
echo "========================================="
echo ""

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker is not running"
    exit 1
fi

# Clean up old containers
echo "[1/3] Cleaning up old containers..."
docker-compose down 2>/dev/null || true

# Build and start containers
echo "[2/3] Building and starting containers..."
docker-compose up -d --build

# Wait for containers to be ready
echo "[3/3] Waiting for SSH to be ready..."
sleep 5

# Test SSH connectivity
echo ""
echo "Testing SSH connectivity..."
for ip in 172.20.0.10 172.20.0.11 172.20.0.20; do
    if timeout 5 bash -c "echo > /dev/tcp/$ip/22" 2>/dev/null; then
        echo "  ✓ $ip:22 accessible"
    else
        echo "  ✗ $ip:22 not accessible yet"
    fi
done

echo ""
echo "========================================="
echo "Test environment ready!"
echo "========================================="
echo ""
echo "Container IPs:"
echo "  test-osd-01: 172.20.0.10"
echo "  test-osd-02: 172.20.0.11"
echo "  test-mon-01: 172.20.0.20"
echo ""
echo "SSH credentials: root / testpass"
echo ""
echo "Test with Ansible:"
echo "  cd .."
echo "  ansible -i test/inventory-test.yml all -m ping"
echo ""
echo "Test SSH manually:"
echo "  ssh root@172.20.0.10  (password: testpass)"
echo ""
echo "Stop environment:"
echo "  docker-compose down"
echo ""
