#!/bin/bash
# IPMI Power Control Script

set -e

IPMI_HOST="${1}"
IPMI_USER="${2}"
IPMI_PASS="${3}"
ACTION="${4:-status}"  # on, off, cycle, reset, status

if [ -z "$IPMI_HOST" ] || [ -z "$IPMI_USER" ] || [ -z "$IPMI_PASS" ]; then
    echo "Usage: $0 <ipmi_host> <username> <password> [action]"
    echo "Actions: on, off, cycle, reset, status (default: status)"
    exit 1
fi

ipmi_exec() {
    ipmitool -I lanplus -H "${IPMI_HOST}" -U "${IPMI_USER}" -P "${IPMI_PASS}" "$@"
}

echo "[${IPMI_HOST}] Executing action: ${ACTION}"

case "${ACTION}" in
    on)
        # Set PXE boot for next boot
        ipmi_exec chassis bootdev pxe options=persistent
        echo "[${IPMI_HOST}] Boot device set to PXE"
        
        # Power on
        ipmi_exec chassis power on
        echo "[${IPMI_HOST}] Power on command sent"
        ;;
    
    off)
        ipmi_exec chassis power off
        echo "[${IPMI_HOST}] Power off command sent"
        ;;
    
    cycle)
        ipmi_exec chassis power cycle
        echo "[${IPMI_HOST}] Power cycle command sent"
        ;;
    
    reset)
        ipmi_exec chassis power reset
        echo "[${IPMI_HOST}] Power reset command sent"
        ;;
    
    status)
        STATUS=$(ipmi_exec chassis power status)
        echo "[${IPMI_HOST}] ${STATUS}"
        ;;
    
    *)
        echo "ERROR: Unknown action: ${ACTION}"
        echo "Valid actions: on, off, cycle, reset, status"
        exit 1
        ;;
esac

exit 0
