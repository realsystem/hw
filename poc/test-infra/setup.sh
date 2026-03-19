#!/bin/bash
# Setup script for infrastructure simulation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Testing Environment Setup"
echo "========================================="
echo ""

# Check Docker
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker is not running"
    exit 1
fi

echo "Choose testing mode:"
echo ""
echo "1) Ansible testing (DHCP + 3 nodes) - Recommended"
echo "2) Terraform testing (Mock Foreman API + 3 nodes)"
echo ""
read -p "Choice (1 or 2): " choice

case $choice in
    1)
        COMPOSE_FILE="docker-compose.simple.yml"
        MODE="ansible"
        echo ""
        echo "Starting Ansible test environment..."
        ;;
    2)
        COMPOSE_FILE="docker-compose.terraform.yml"
        MODE="terraform"
        echo ""
        echo "Starting Terraform test environment..."
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""

echo ""
echo "[1/3] Cleaning up old containers..."
docker-compose -f $COMPOSE_FILE down 2>/dev/null || true

echo "[2/3] Building and starting containers..."
docker-compose -f $COMPOSE_FILE up -d --build

echo "[3/3] Waiting for services to be ready..."
sleep 10

echo ""
echo "========================================="
echo "Environment Ready!"
echo "========================================="
echo ""

if [ "$MODE" = "ansible" ]; then
    echo "Mode: Ansible Testing"
    echo ""
    echo "PXE Server:"
    echo "  - Container: pxe-server"
    echo "  - IP: 172.30.0.10"
    echo "  - Services: DHCP, DNS, TFTP"
    echo ""
    echo "Simulated Nodes:"
    echo "  - node-01: 172.30.0.100 (SSH: localhost:2301)"
    echo "  - node-02: 172.30.0.101 (SSH: localhost:2302)"
    echo "  - node-03: 172.30.0.110 (SSH: localhost:2303)"
    echo ""
    echo "SSH Credentials:"
    echo "  - Username: root"
    echo "  - Password: testpass"
    echo ""
    echo "Quick Test Commands:"
    echo ""
    echo "  # Test Ansible (run from poc/ansible directory)"
    echo "  cd ../ansible"
    echo "  ansible -i ../test-infra/inventory-sim.yml all -m ping"
    echo "  ansible-playbook -i ../test-infra/inventory-sim.yml playbooks/ceph_baseline.yml"
    echo ""
    echo "  # Check DHCP logs"
    echo "  docker logs pxe-server"
    echo ""
else
    echo "Mode: Terraform Testing"
    echo ""
    echo "Mock Foreman API:"
    echo "  - URL: http://localhost:3000"
    echo "  - Username: admin"
    echo "  - Password: changeme123"
    echo ""
    echo "Simulated Nodes:"
    echo "  - node-01: 172.35.0.100 (SSH: localhost:2301)"
    echo "  - node-02: 172.35.0.101 (SSH: localhost:2302)"
    echo "  - node-03: 172.35.0.110 (SSH: localhost:2303)"
    echo ""
    echo "Quick Test Commands:"
    echo ""
    echo "  # Test API status"
    echo "  curl http://localhost:3000/api/status"
    echo ""
    echo "  # Test Terraform (provider)"
    echo "  cd ../terraform/00-provider"
    echo "  terraform init"
    echo "  terraform plan"
    echo "  terraform apply"
    echo ""
    echo "  # Test Terraform (create resources)"
    echo "  cd ../01-foreman-config"
    echo "  terraform init"
    echo "  terraform plan"
    echo "  terraform apply"
    echo ""
    echo "  # Verify resources created"
    echo "  curl -u admin:changeme123 http://localhost:3000/api/v2/hostgroups | jq ."
    echo ""
fi

echo "Cleanup:"
echo "  docker-compose -f $COMPOSE_FILE down"
echo ""

echo "Cleanup:"
echo "  docker-compose -f $COMPOSE_FILE down"
echo ""
