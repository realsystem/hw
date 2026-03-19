#!/bin/bash
# IPMI Power Control Script
#
# Powers on servers and sets PXE boot for discovery

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# IPMI credentials (can be overridden via environment)
IPMI_USER="${IPMI_USER:-ADMIN}"
IPMI_PASS="${IPMI_PASS:-ADMIN}"

# Function to execute IPMI command
ipmi_exec() {
    local ipmi_host=$1
    shift

    ipmitool -I lanplus \
        -H "$ipmi_host" \
        -U "$IPMI_USER" \
        -P "$IPMI_PASS" \
        -L ADMINISTRATOR \
        "$@"
}

# Function to power on and set PXE boot
power_on_pxe() {
    local ipmi_host=$1

    echo -e "${YELLOW}[${ipmi_host}]${NC} Setting boot device to PXE..."
    ipmi_exec "$ipmi_host" chassis bootdev pxe options=persistent

    echo -e "${YELLOW}[${ipmi_host}]${NC} Powering on..."
    ipmi_exec "$ipmi_host" chassis power on

    echo -e "${GREEN}[${ipmi_host}]${NC} Power on command sent"
}

# Function to check power status
check_status() {
    local ipmi_host=$1

    echo -e "${YELLOW}[${ipmi_host}]${NC} Checking power status..."
    ipmi_exec "$ipmi_host" chassis power status
}

# Main
if [ $# -eq 0 ]; then
    echo "Usage: $0 <ipmi_address> [ipmi_address2] [ipmi_address3] ..."
    echo ""
    echo "Example:"
    echo "  $0 10.20.7.12 10.20.7.13 10.20.7.14"
    echo ""
    echo "Environment variables:"
    echo "  IPMI_USER - IPMI username (default: ADMIN)"
    echo "  IPMI_PASS - IPMI password (default: ADMIN)"
    exit 1
fi

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  IPMI Power On Script                                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Power on all specified hosts
for ipmi_host in "$@"; do
    power_on_pxe "$ipmi_host"
    echo ""
done

echo "Waiting 30 seconds for servers to start..."
sleep 30

echo ""
echo "Checking power status:"
for ipmi_host in "$@"; do
    check_status "$ipmi_host"
done

echo ""
echo -e "${GREEN}✓${NC} All commands sent successfully"
echo ""
echo "Next steps:"
echo "  1. Servers will PXE boot and enter discovery mode"
echo "  2. Wait 5-10 minutes for hardware discovery"
echo "  3. Check Foreman UI: https://foreman.example.com/discovered_hosts"
echo "  4. Run Terraform to provision discovered nodes"
