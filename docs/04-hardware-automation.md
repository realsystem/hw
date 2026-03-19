# Supermicro X9 Hardware Automation

## Overview

Comprehensive automation for Supermicro X9 series servers, covering IPMI management, BIOS configuration, firmware updates, and common hardware issue handling.

---

## Supermicro X9 Platform Overview

### Supported Models

**Storage-Optimized:**
- **X9DRi-LN4+/X9DR3-LN4+**: Dual socket, excellent for Ceph OSD nodes
- **X9DRD-iF/EF**: 12-16 SATA/SAS ports
- **X9DRH-iF/iT/iTF**: High-density storage (24+ drives)

**Compute-Optimized:**
- **X9DRW**: Workstation board (MON/MGR nodes)
- **X9SRL-F**: Single socket (lightweight mgmt nodes)

### Key Features for Ceph

**Advantages:**
- IPMI 2.0 with KVM-over-IP
- Dedicated IPMI NIC (isolated management)
- LSI HBA support (IT mode for JBOD)
- Multiple PCIe slots (10GbE NICs, NVMe adapters)
- Good cooling for dense storage
- ECC memory support

**Limitations:**
- Older platform (2012-2014 era)
- No NVMe

 boot support (BIOS limitation)
- IPMI firmware can be buggy (requires updates)
- Fan control can be aggressive

---

## IPMI Automation Framework

### IPMI Configuration

**Network Setup:**

```
Management Network: 10.20.0.0/16
IPMI Subnet: 10.20.0.0/20 (10.20.0.1 - 10.20.15.254)

Naming Convention:
  ceph-osd-r07-u12-ipmi.mgmt.example.com  10.20.7.12
```

**Default Credentials:**
```
Username: ADMIN
Password: ADMIN (CHANGE IMMEDIATELY)
```

### Core IPMI Wrapper Script

```bash
#!/bin/bash
# /usr/local/bin/ipmi-exec.sh
#
# Wrapper for ipmitool with credential management and error handling

set -euo pipefail

IPMI_HOST="$1"
IPMI_COMMAND="${@:2}"

# Credential vault (integrate with HashiCorp Vault or file-based)
CRED_FILE="/etc/foreman-proxy/ipmi-credentials.yml"

# Extract credentials
IPMI_USER=$(yq eval ".hosts.\"$IPMI_HOST\".user // .default.user" "$CRED_FILE")
IPMI_PASS=$(yq eval ".hosts.\"$IPMI_HOST\".pass // .default.pass" "$CRED_FILE")

# Validate credentials exist
if [ -z "$IPMI_USER" ] || [ -z "$IPMI_PASS" ]; then
    echo "ERROR: No credentials found for $IPMI_HOST" >&2
    exit 1
fi

# Execute ipmitool command
ipmitool -I lanplus \
    -H "$IPMI_HOST" \
    -U "$IPMI_USER" \
    -P "$IPMI_PASS" \
    -L ADMINISTRATOR \
    $IPMI_COMMAND

exit $?
```

**Credential File Format:**
```yaml
# /etc/foreman-proxy/ipmi-credentials.yml
default:
  user: ADMIN
  pass: changeme123

hosts:
  10.20.7.12:
    user: provisioning
    pass: SecurePass123!
  10.20.7.13:
    user: provisioning
    pass: SecurePass124!
```

### Power Management

```bash
#!/bin/bash
# /usr/local/bin/ipmi-power.sh <host> <action>

IPMI_HOST=$1
ACTION=$2

case $ACTION in
    on)
        ipmi-exec.sh "$IPMI_HOST" chassis power on
        ;;
    off)
        ipmi-exec.sh "$IPMI_HOST" chassis power off
        ;;
    cycle)
        ipmi-exec.sh "$IPMI_HOST" chassis power cycle
        ;;
    reset)
        ipmi-exec.sh "$IPMI_HOST" chassis power reset
        ;;
    soft)
        ipmi-exec.sh "$IPMI_HOST" chassis power soft
        ;;
    status)
        ipmi-exec.sh "$IPMI_HOST" chassis power status
        ;;
    *)
        echo "Usage: $0 <host> <on|off|cycle|reset|soft|status>"
        exit 1
        ;;
esac
```

### Boot Device Control

```bash
#!/bin/bash
# /usr/local/bin/ipmi-bootdev.sh <host> <device> [persistent]

IPMI_HOST=$1
DEVICE=$2
PERSISTENT=${3:-""}

case $DEVICE in
    pxe|network)
        BOOT_DEV="pxe"
        ;;
    disk|hdd)
        BOOT_DEV="disk"
        ;;
    cdrom)
        BOOT_DEV="cdrom"
        ;;
    bios)
        BOOT_DEV="bios"
        ;;
    *)
        echo "ERROR: Invalid boot device: $DEVICE"
        exit 1
        ;;
esac

OPTIONS=""
if [ "$PERSISTENT" == "persistent" ]; then
    OPTIONS="options=persistent"
else
    OPTIONS="options=efiboot"
fi

ipmi-exec.sh "$IPMI_HOST" chassis bootdev "$BOOT_DEV" "$OPTIONS"

echo "Boot device set to $BOOT_DEV ($OPTIONS) on $IPMI_HOST"
```

### Serial-Over-LAN (SOL) Capture

```bash
#!/bin/bash
# /usr/local/bin/ipmi-sol-capture.sh <host> <output_file>

IPMI_HOST=$1
OUTPUT_FILE=${2:-"/var/log/sol/$IPMI_HOST-$(date +%Y%m%d-%H%M%S).log"}

mkdir -p $(dirname "$OUTPUT_FILE")

echo "Capturing SOL from $IPMI_HOST to $OUTPUT_FILE"
echo "Press Ctrl+] then . to exit"

ipmi-exec.sh "$IPMI_HOST" sol activate | tee "$OUTPUT_FILE"
```

### Sensor Monitoring

```bash
#!/bin/bash
# /usr/local/bin/ipmi-sensors.sh <host> [sensor_type]

IPMI_HOST=$1
SENSOR_TYPE=${2:-""}

if [ -z "$SENSOR_TYPE" ]; then
    # All sensors
    ipmi-exec.sh "$IPMI_HOST" sdr list
else
    # Filter by type (temp, fan, voltage, etc.)
    ipmi-exec.sh "$IPMI_HOST" sdr type "$SENSOR_TYPE"
fi
```

**Example Output:**
```
Temp             | 01h | ok  |  3.1 | 35 degrees C
Temp             | 02h | ok  |  3.2 | 34 degrees C
FAN1             | 41h | ok  |  7.1 | 4200 RPM
FAN2             | 42h | ok  |  7.2 | 4100 RPM
PS1 Status       | C8h | ok  | 10.1 | Presence detected
PS2 Status       | C9h | ok  | 10.2 | Presence detected
```

### Bulk IPMI Operations

```bash
#!/bin/bash
# /usr/local/bin/ipmi-bulk-exec.sh <host_file> <command>

HOST_FILE=$1
COMMAND="${@:2}"

if [ ! -f "$HOST_FILE" ]; then
    echo "ERROR: Host file not found: $HOST_FILE"
    exit 1
fi

# Parallel execution with GNU parallel
cat "$HOST_FILE" | parallel -j 20 "ipmi-exec.sh {} $COMMAND"
```

**Example Usage:**
```bash
# Power on 100 nodes simultaneously
echo "10.20.7.{12..111}" | tr ' ' '\n' > /tmp/nodes.txt
ipmi-bulk-exec.sh /tmp/nodes.txt chassis power on

# Check power status
ipmi-bulk-exec.sh /tmp/nodes.txt chassis power status | grep -c "Chassis Power is on"
```

---

## BIOS Configuration Management

### BIOS Settings for Ceph

**Optimal Configuration:**

| Setting | Value | Rationale |
|---------|-------|-----------|
| **Hyper-Threading** | Enabled | More threads for Ceph daemons |
| **Turbo Boost** | Disabled | Consistent performance, avoid thermal throttling |
| **C-States** | C1E only | Reduce latency, slight power increase |
| **P-States** | Disabled | OS manages CPU frequency |
| **NUMA** | Enabled | Better memory locality for Ceph |
| **VT-d** | Enabled | Future containerization support |
| **SR-IOV** | Enabled | Network performance |
| **Boot Mode** | BIOS (not UEFI) | X9 UEFI less mature |
| **Boot Order** | 1. Network, 2. HDD | PXE first, fallback to disk |
| **Quiet Boot** | Disabled | See POST messages via SOL |
| **AC Power Recovery** | Last State | Survive datacenter power events |

### BIOS Configuration via IPMI

**Read Current BIOS Settings:**
```bash
#!/bin/bash
# ipmi-bios-dump.sh <host>

IPMI_HOST=$1

ipmi-exec.sh "$IPMI_HOST" raw 0x30 0x02 0x01 0x00 0x00 0x00 0x00 0x00
# Output: Binary blob (decode with supermicro tools)
```

**Set BIOS Settings (Limited Support):**

Supermicro X9 has limited BIOS modification via IPMI. Most settings require:
1. **Interactive BIOS setup** (via IPMI KVM)
2. **sum utility** (Supermicro Update Manager - CLI tool)

### Using Supermicro SUM (Update Manager)

**Installation:**
```bash
# Download from Supermicro website
wget https://www.supermicro.com/SwDownload/UserInfo/sum_2.11.0_Linux_x86_64_20230808.tar.gz
tar -xzf sum_2.11.0_Linux_x86_64_20230808.tar.gz
cd sum_2.11.0_Linux_x86_64
chmod +x sum
```

**Read BIOS Configuration:**
```bash
./sum -i $IPMI_HOST -u $IPMI_USER -p $IPMI_PASS -c GetCurrentBiosCfg --file current-bios.xml
```

**Modify and Apply:**
```bash
# Edit current-bios.xml
vim current-bios.xml

# Apply changes
./sum -i $IPMI_HOST -u $IPMI_USER -p $IPMI_PASS -c ChangeBiosCfg --file modified-bios.xml

# Reboot required
ipmi-power.sh $IPMI_HOST reset
```

**Example BIOS XML Snippet:**
```xml
<BiosConfig>
  <Menu name="Advanced">
    <Setting name="Hyper-Threading" order="1">Enabled</Setting>
    <Setting name="Turbo Mode" order="2">Disabled</Setting>
  </Menu>
  <Menu name="Boot">
    <Setting name="Boot Option #1">Network</Setting>
    <Setting name="Boot Option #2">Hard Disk</Setting>
  </Menu>
</BiosConfig>
```

### Automated BIOS Standardization

```bash
#!/bin/bash
# /usr/local/bin/bios-standardize.sh <host>

IPMI_HOST=$1
GOLDEN_BIOS="/etc/provisioning/bios-templates/x9-ceph-osd.xml"

echo "Standardizing BIOS for $IPMI_HOST..."

# Backup current BIOS
sum -i $IPMI_HOST -u $USER -p $PASS -c GetCurrentBiosCfg --file /tmp/${IPMI_HOST}-bios-backup.xml

# Apply golden configuration
sum -i $IPMI_HOST -u $USER -p $PASS -c ChangeBiosCfg --file $GOLDEN_BIOS

if [ $? -eq 0 ]; then
    echo "BIOS configuration applied successfully"
    echo "Rebooting to activate changes..."
    ipmi-power.sh $IPMI_HOST reset
else
    echo "ERROR: BIOS configuration failed"
    exit 1
fi
```

---

## Firmware Management

### Firmware Inventory

**Check Versions:**
```bash
#!/bin/bash
# ipmi-firmware-inventory.sh <host>

IPMI_HOST=$1

echo "=== Firmware Inventory for $IPMI_HOST ==="

# IPMI firmware version
echo -n "IPMI: "
ipmi-exec.sh "$IPMI_HOST" mc info | grep "Firmware Revision" | awk '{print $4}'

# BIOS version
echo -n "BIOS: "
ipmi-exec.sh "$IPMI_HOST" fru print 0 | grep "Product Version" | awk '{print $4}'

# BMC version
echo -n "BMC: "
ipmi-exec.sh "$IPMI_HOST" mc info | grep "Manufacturer ID" | awk '{print $4}'
```

### Firmware Update Process

**Supermicro X9 Common Firmware:**

| Component | Current (Typical) | Recommended | Notes |
|-----------|-------------------|-------------|-------|
| BIOS | 3.0 - 3.2 | 3.4 (latest stable) | Security fixes, NVMe support |
| IPMI/BMC | 3.50 - 3.77 | 3.88 | Bug fixes, KVM improvements |
| NIC (Intel) | Various | Latest | Performance, security |
| HBA (LSI) | P19 - P20 | P20 | IT mode compatibility |

**Firmware Update via SUM:**

```bash
#!/bin/bash
# firmware-update.sh <host> <firmware_type>

IPMI_HOST=$1
FW_TYPE=$2
FW_DIR="/srv/firmware/supermicro/x9"

case $FW_TYPE in
    bios)
        FW_FILE="$FW_DIR/X9DRI_341.bin"
        ;;
    ipmi|bmc)
        FW_FILE="$FW_DIR/SMT_X9_388.bin"
        ;;
    *)
        echo "ERROR: Unknown firmware type: $FW_TYPE"
        exit 1
        ;;
esac

if [ ! -f "$FW_FILE" ]; then
    echo "ERROR: Firmware file not found: $FW_FILE"
    exit 1
fi

echo "Updating $FW_TYPE firmware on $IPMI_HOST..."
echo "Firmware file: $FW_FILE"

# Upload and flash
sum -i $IPMI_HOST -u $USER -p $PASS -c UpdateBios --file $FW_FILE --reboot

# Monitor progress
while true; do
    STATUS=$(ipmi-exec.sh "$IPMI_HOST" chassis power status 2>/dev/null || echo "updating")
    if [[ "$STATUS" =~ "Chassis Power is on" ]]; then
        echo "Update complete, system online"
        break
    fi
    echo "Waiting for update to complete..."
    sleep 30
done
```

**Safe Update Workflow:**

1. **Backup BIOS config** (shown above)
2. **Update in batches** (1 rack at a time)
3. **Validation window** (24 hours before next batch)
4. **Rollback plan** (keep old firmware images)

```bash
# Batch firmware update
for rack in r07 r08 r09; do
    echo "=== Updating rack $rack ==="

    HOSTS=$(foreman-cli host list --search "rack=$rack" --fields name | tail -n +2)

    for host in $HOSTS; do
        IPMI=$(dig +short ${host}-ipmi.mgmt.example.com)
        firmware-update.sh $IPMI bios
        sleep 300  # 5 min between nodes
    done

    echo "Rack $rack complete. Waiting 24h for validation..."
    sleep 86400
done
```

---

## HBA/RAID Controller Configuration

### LSI HBA in IT Mode (JBOD)

**Why IT Mode?**
- Ceph manages redundancy (no RAID needed)
- Direct disk access (better performance)
- SMART passthrough
- No RAID controller overhead

**Check Current Mode:**
```bash
# Install sas2flash utility
apt-get install sas2flash

# Check controller info
sas2flash -listall
sas2flash -c 0 -list

# Example output:
#   Firmware Version: 20.00.07.00 (IT mode)
#   or
#   Firmware Version: 23.33.00.00 (IR mode - BAD for Ceph)
```

**Flash to IT Mode:**

```bash
#!/bin/bash
# lsi-flash-it-mode.sh
#
# WARNING: This wipes RAID config if present!

set -e

# Download IT mode firmware from Broadcom/LSI
FW_FILE="/srv/firmware/lsi/9211-8i-IT-20.00.07.00.bin"

# Erase existing firmware
sas2flash -c 0 -o -e 6

# Flash IT mode firmware
sas2flash -c 0 -f "$FW_FILE"

# Write SAS address (use original from label or generate)
sas2flash -c 0 -o -sasadd 500605bxxxxxxxxx

echo "IT mode flash complete. Reboot required."
```

**Verification:**
```bash
lspci | grep -i lsi
# Should show: LSI Logic / Symbios Logic SAS2008 PCI-Express Fusion-MPT SAS-2 [Falcon]

dmesg | grep mpt
# Should NOT show: megaraid

lsscsi
# Should show direct /dev/sd* devices, not /dev/sda (RAID volume)
```

---

## Common Supermicro X9 Issues

### Issue 1: IPMI Unresponsive

**Symptoms:**
- IPMI web interface timeout
- `ipmitool` commands hang
- Ping fails

**Diagnosis:**
```bash
# Check IPMI NIC link
ipmi-exec.sh $IPMI_HOST raw 0x0c 0x02 0x01 0x01 0x00
# Returns link status

# Check BMC status
ipmi-exec.sh $IPMI_HOST mc info
```

**Solution 1: BMC Cold Reset**
```bash
ipmi-exec.sh $IPMI_HOST mc reset cold
# Wait 2-3 minutes for BMC to reboot
```

**Solution 2: AC Power Cycle**
```bash
# Only if BMC reset fails
# Requires PDU access or physical presence
echo "Power cycle required via PDU or physical access"
```

**Prevention:**
- Update IPMI firmware to 3.88+
- Disable unused IPMI features (Java KVM if using HTML5)

### Issue 2: Fan Speed Stuck at 100%

**Symptoms:**
- Loud noise
- All fans at maximum RPM
- Temperature normal

**Cause:**
- IPMI lost sensor readings
- Fan control algorithm error

**Solution:**
```bash
# Enable automatic fan control
ipmi-exec.sh $IPMI_HOST raw 0x30 0x45 0x01 0x00

# Or set manual fan speed (%)
FAN_DUTY=40  # 40%
HEX_DUTY=$(printf '%02x' $FAN_DUTY)
ipmi-exec.sh $IPMI_HOST raw 0x30 0x45 0x01 0x$HEX_DUTY
```

**Permanent Fix:**
```bash
# Add to post-provisioning script
cat > /etc/rc.local <<'EOF'
#!/bin/bash
# Set optimal fan speed for Ceph cluster
ipmitool raw 0x30 0x45 0x01 0x30  # 48% duty cycle
EOF
chmod +x /etc/rc.local
```

### Issue 3: Boot Device Not Found After Provisioning

**Symptoms:**
- PXE boots repeatedly
- "No bootable device" error
- BIOS shows empty boot order

**Cause:**
- Boot order not saved after install
- GRUB installation failed

**Diagnosis:**
```bash
# Check boot order via IPMI
ipmi-exec.sh $IPMI_HOST chassis bootparam get 5

# Serial console check
ipmi-sol-capture.sh $IPMI_HOST /tmp/boot-debug.log
# Look for GRUB messages or error
```

**Solution:**
```bash
# Set boot device to disk permanently
ipmi-bootdev.sh $IPMI_HOST disk persistent

# Power cycle
ipmi-power.sh $IPMI_HOST cycle
```

### Issue 4: Memory Errors

**Symptoms:**
- Node crashes randomly
- Kernel panics
- ECC memory errors in logs

**Diagnosis:**
```bash
# Check IPMI SEL (System Event Log)
ipmi-exec.sh $IPMI_HOST sel list | grep -i "memory\|ecc\|dimm"

# Example output showing bad DIMM:
# 142 | 03/18/2026 | 10:30:00 | Memory | Correctable ECC | Asserted | DIMM_P1_B1
```

**Solution:**
```bash
# Identify faulty DIMM location (from SEL)
DIMM_LOCATION="P1_B1"  # Processor 1, Bank 1

# Decommission node from Ceph
# Replace DIMM physically
# Re-provision
```

**Prevention:**
- Run memtest86+ during discovery phase
- Monitor SEL logs daily

### Issue 5: NIC Firmware Mismatch

**Symptoms:**
- Network drops
- Slow 10GbE performance
- Interface reset errors in dmesg

**Diagnosis:**
```bash
ethtool -i eth2
# Firmware version: 14.0.23

# Check for known issues
# Consult Intel X520/X540 firmware changelog
```

**Solution:**
```bash
# Update NIC firmware
apt-get install intel-ixgbe-dkms

# Or use Intel tools
cd /srv/firmware/intel/
./nvmupdate64e -u -l

# Reboot required
reboot
```

---

## Automated Health Checks

### Pre-Provisioning Hardware Validation

```bash
#!/bin/bash
# /usr/local/bin/hardware-precheck.sh <ipmi_host>

IPMI_HOST=$1
ERRORS=0

echo "=== Hardware Pre-Check: $IPMI_HOST ==="

# 1. Power status
STATUS=$(ipmi-power.sh $IPMI_HOST status)
if [[ ! "$STATUS" =~ "on" ]]; then
    echo " Server is powered off"
    ERRORS=$((ERRORS + 1))
else
    echo " Server powered on"
fi

# 2. Temperature sensors
TEMPS=$(ipmi-exec.sh "$IPMI_HOST" sdr type temp | grep degrees | awk '{print $NF}')
for temp in $TEMPS; do
    TEMP_VAL=${temp%%degrees*}
    if [ $TEMP_VAL -gt 75 ]; then
        echo " High temperature: ${temp}"
        ERRORS=$((ERRORS + 1))
    fi
done
echo " Temperatures normal"

# 3. Fan status
FANS=$(ipmi-exec.sh "$IPMI_HOST" sdr type fan | grep RPM | awk '{print $NF}')
for fan in $FANS; do
    FAN_RPM=${fan%%RPM*}
    if [ $FAN_RPM -lt 1000 ]; then
        echo " Fan failure or low speed: ${fan}"
        ERRORS=$((ERRORS + 1))
    fi
done
echo " Fans operational"

# 4. Power supply status
PS=$(ipmi-exec.sh "$IPMI_HOST" sdr | grep "PS.*Status" | grep -v "Presence detected")
if [ -n "$PS" ]; then
    echo " Power supply issue: $PS"
    ERRORS=$((ERRORS + 1))
else
    echo " Power supplies OK"
fi

# 5. SEL critical errors
SEL_CRIT=$(ipmi-exec.sh "$IPMI_HOST" sel list | grep -i "critical\|non-recoverable" | wc -l)
if [ $SEL_CRIT -gt 0 ]; then
    echo " Critical events in SEL: $SEL_CRIT"
    ipmi-exec.sh "$IPMI_HOST" sel list | grep -i "critical\|non-recoverable"
    ERRORS=$((ERRORS + 1))
else
    echo " No critical SEL events"
fi

# Summary
echo ""
if [ $ERRORS -eq 0 ]; then
    echo " Hardware pre-check PASSED"
    exit 0
else
    echo " Hardware pre-check FAILED ($ERRORS errors)"
    exit 1
fi
```

### Integration with Foreman Discovery

```ruby
# Foreman discovery hook: /etc/foreman-proxy/settings.d/discovery.yml

# Run hardware pre-check before approving
:discovery_pre_approve_hook: /usr/local/bin/hardware-precheck.sh
```

---

## IPMI Security Best Practices

### Credential Management

```bash
# Rotate IPMI passwords quarterly
/usr/local/bin/ipmi-password-rotate.sh

#!/bin/bash
# Generate secure password
NEW_PASS=$(pwgen -s 16 1)

# Update on all nodes
while read IPMI_HOST; do
    ipmi-exec.sh "$IPMI_HOST" user set password 2 "$NEW_PASS"
    # Update credential vault
    yq eval ".hosts.\"$IPMI_HOST\".pass = \"$NEW_PASS\"" -i /etc/foreman-proxy/ipmi-credentials.yml
done < /etc/provisioning/ipmi-hosts.txt

echo "Password rotation complete"
```

### Network Isolation

```
IPMI VLAN (20): 10.20.0.0/16
- Firewall rules:
   Allow from provisioning servers (10.10.0.0/16)
  ✗ Deny from production networks
  ✗ Deny from Internet
```

### Disable Unnecessary Services

```bash
# Disable IPMI web interface (use CLI only)
ipmi-exec.sh $IPMI_HOST raw 0x0c 0x01 0x01 0x80 0x00 0x00

# Disable IPMI over LAN (if not needed)
# ipmi-exec.sh $IPMI_HOST lan set 1 access off
```

---

## Monitoring Integration

### Prometheus IPMI Exporter

```yaml
# /etc/prometheus/prometheus.yml

scrape_configs:
  - job_name: 'ipmi'
    scrape_interval: 60s
    scrape_timeout: 30s
    metrics_path: /metrics
    static_configs:
      - targets:
          - 10.20.7.12:9290  # ceph-osd-r07-u12-ipmi
          - 10.20.7.13:9290
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
```

**Deploy ipmi_exporter:**
```bash
docker run -d \
  --name ipmi_exporter \
  -p 9290:9290 \
  -e IPMI_USER=monitoring \
  -e IPMI_PASSWORD=SecurePass \
  prometheuscommunity/ipmi-exporter:latest \
  --config.file=/config.yml
```

---

## Summary

Supermicro X9 automation provides:

1. **IPMI Management**: Power, boot, sensors, SOL
2. **BIOS Standardization**: Consistent performance settings
3. **Firmware Updates**: Centralized, versioned, safe
4. **HBA Configuration**: IT mode for Ceph
5. **Issue Resolution**: Known problems, solutions, prevention
6. **Security**: Credential management, network isolation
7. **Monitoring**: Health checks, metrics integration

**Next**: Ceph-ready node configuration (network tuning, kernel parameters, storage preparation).
