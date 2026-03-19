# Node Lifecycle Management

## Overview

The node lifecycle defines the complete journey from physical hardware installation to a Ceph-ready compute node. This model ensures consistent, auditable, and automated transitions through well-defined states.

---

## State Machine

```
                    ┌──────────────┐
                    │              │
                    │   PHYSICAL   │  (Hardware racked, cabled, powered off)
                    │              │
                    └──────┬───────┘
                           │
                           │ Power on detected via IPMI scan
                           │ OR manual registration
                           ▼
                    ┌──────────────┐
                    │              │
              ┌────►│     NEW      │  (Unknown hardware detected)
              │     │              │
              │     └──────┬───────┘
              │            │
              │            │ Trigger discovery
              │            ▼
              │     ┌──────────────┐
              │     │              │
              │     │  DISCOVERING │  (Hardware inspection in progress)
              │     │              │
              │     └──────┬───────┘
              │            │
              │            │ Discovery complete, facts collected
              │            ▼
              │     ┌──────────────┐
              │     │              │
              └─────┤  DISCOVERED  │  (Awaiting approval or auto-provision)
                    │              │
                    └──────┬───────┘
                           │
                           │ Manual approval OR auto-approve rule match
                           ▼
                    ┌──────────────┐
                    │              │
                    │   APPROVED   │  (Ready for provisioning)
                    │              │
                    └──────┬───────┘
                           │
                           │ Provision workflow initiated
                           ▼
                    ┌──────────────┐
                    │              │
              ┌────►│ PROVISIONING │  (OS installation in progress)
              │     │              │
              │     └──────┬───────┘
              │            │
              │            │ Installation successful
              │            ▼
              │     ┌──────────────┐
              │     │              │
              │     │ PROVISIONED  │  (OS installed, first boot complete)
              │     │              │
              │     └──────┬───────┘
              │            │
              │            │ Configuration workflow triggered
              │            ▼
              │     ┌──────────────┐
              │     │              │
              │     │ CONFIGURING  │  (Ansible applying Ceph-ready config)
              │     │              │
              │     └──────┬───────┘
              │            │
              │            │ Configuration complete
              │            ▼
              │     ┌──────────────┐
              │     │              │
              │     │ CONFIGURED   │  (Base config applied)
              │     │              │
              │     └──────┬───────┘
              │            │
              │            │ Validation tests triggered
              │            ▼
              │     ┌──────────────┐
              │     │              │
              │     │  VALIDATING  │  (Running health checks)
              │     │              │
              │     └──────┬───────┘
              │            │
              │            │ All validations passed
              │            ▼
              │     ┌──────────────┐
              │     │              │
              │     │  VALIDATED   │  (Node verified healthy)
              │     │              │
              │     └──────┬───────┘
              │            │
              │            │ Mark ready for Ceph
              │            ▼
              │     ┌──────────────┐
              │     │              │
              │     │ READY_CEPH   │  (Available for Ceph deployment)
              │     │              │
              │     └──────┬───────┘
              │            │
              │            │ ceph-ansible deploys OSD/MON/etc
              │            ▼
              │     ┌──────────────┐
              │     │              │
              │     │  IN_SERVICE  │  (Active Ceph cluster member)
              │     │              │
              │     └──────┬───────┘
              │            │
              │            │ Decommission for maintenance/replacement
              │            ▼
              │     ┌──────────────┐
              │     │              │
              │     │ DECOMISSION  │  (Being removed from cluster)
              │     │              │
              │     └──────┬───────┘
              │            │
              │            │ Data migrated, OSD removed
              │            └──────────┐
              │                       │
              │                       ▼
              │            ┌──────────────────┐
              │            │                  │
              │            │  DECOMMISSIONED  │
              │            │                  │
              │            └──────────────────┘
              │                       │
              │                       │ Reprovision OR retire
              │                       ▼
              │                  [Physical removal or loop back to NEW]
              │
              │
              │  ┌──────────────────────────────────────────────────┐
              │  │                                                  │
              └──┤  ERROR STATES (from any transition)              │
                 │                                                  │
                 │  • DISCOVERY_FAILED                              │
                 │  • PROVISION_FAILED                              │
                 │  • CONFIG_FAILED                                 │
                 │  • VALIDATION_FAILED                             │
                 │                                                  │
                 │  All error states allow:                         │
                 │    - Manual retry                                │
                 │    - Debugging / investigation                   │
                 │    - Reset to NEW state                          │
                 └──────────────────────────────────────────────────┘
```

---

## State Definitions

### PHYSICAL
**Description**: Hardware is physically installed in datacenter but not yet managed by provisioning system.

**Characteristics:**
- Racked and cabled
- Connected to management network
- IPMI/BMC accessible
- Power state unknown

**Entry Conditions:**
- Physical installation complete
- Network cables connected
- Power available (may be off)

**Exit Conditions:**
- IPMI responds to ping/scan
- Manual registration via API/UI

**Automation:**
```bash
# IPMI network scanner (periodic)
nmap -p 623 -sT --open 10.20.0.0/24 | \
  parse_new_ipmi_addresses | \
  foreman-cli host create --name unknown-$MAC
```

---

### NEW
**Description**: System detected but no hardware facts collected.

**Characteristics:**
- IPMI address known
- MAC address may be known
- No CPU, RAM, disk information
- Default credentials or registered credentials

**Actions:**
- Queue for discovery
- Assign to discovery pool
- Wait for manual trigger

**Foreman Representation:**
```json
{
  "name": "unknown-001122334455",
  "build": false,
  "managed": false,
  "compute_resource": "ipmi-pool-rack7",
  "status": "new"
}
```

---

### DISCOVERING
**Description**: Hardware inspection actively running.

**Inspection Process:**
1. **PXE boot discovery image** (Foreman Discovery Plugin or custom)
2. **Collect hardware facts**:
   - CPU model, cores, frequency
   - RAM size and configuration
   - Disk inventory (model, size, serial, type)
   - NIC count, MAC addresses, firmware
   - BIOS version
   - IPMI firmware version
   - PCIe devices
3. **Run hardware tests** (optional):
   - Memory test (memtest86+)
   - Disk SMART status
   - Network link tests
4. **Report facts to Foreman**
5. **Shutdown or leave in discovery loop**

**Discovery Image:**
- Debian-based minimal live OS
- facter, lshw, dmidecode, smartctl
- Custom fact collection scripts
- Callback to Foreman API

**Timeout:** 30 minutes (configurable)

**Failure Handling:**
- No callback  DISCOVERY_FAILED
- Incomplete facts  manual review
- Hardware issues  flag for RMA

---

### DISCOVERED
**Description**: Hardware facts collected, awaiting approval.

**Fact Database Example:**
```yaml
hostname: node-rack7-u12
cpu:
  model: Intel Xeon E5-2680 v2
  cores: 20
  threads: 40
  frequency: 2.8GHz
memory:
  total: 256GB
  dimms: 16x 16GB DDR3 ECC
disks:
  - device: /dev/sda
    model: Intel S3700 400GB
    size: 400GB
    type: SSD
    serial: CVMP4321...
  - device: /dev/sdb
    model: HGST HUS726060ALA640
    size: 6TB
    type: HDD
    serial: K4H12345...
  - device: /dev/sdc
    model: HGST HUS726060ALA640
    size: 6TB
    type: HDD
    serial: K4H12346...
  # ... up to 12 disks
nics:
  - mac: 00:25:90:aa:bb:cc
    interface: eth0
    speed: 1Gbps
  - mac: 00:25:90:aa:bb:cd
    interface: eth1
    speed: 1Gbps
  - mac: 00:25:90:aa:bb:ce
    interface: eth2
    speed: 10Gbps
  - mac: 00:25:90:aa:bb:cf
    interface: eth3
    speed: 10Gbps
ipmi:
  ip: 10.20.7.45
  mac: 00:25:90:aa:bb:d0
  firmware: 3.77
bios:
  version: 3.2
  vendor: American Megatrends
```

**Auto-Approval Rules:**
Apply automatic approval if node matches:
```yaml
auto_approve_rules:
  - name: "Supermicro X9 Ceph OSD"
    conditions:
      cpu_cores: ">= 16"
      memory_gb: ">= 128"
      disk_count: ">= 10"
      disk_types_include: ["SSD", "HDD"]
      manufacturer: "Supermicro"
      model_regex: "X9.*"
    actions:
      - approve
      - assign_hostgroup: "ceph-osd-nodes"
      - assign_subnet: "ceph-cluster"
      - set_build: true

  - name: "Supermicro X9 Ceph Monitor"
    conditions:
      cpu_cores: ">= 8"
      memory_gb: ">= 64"
      disk_ssd_count: ">= 2"
      manufacturer: "Supermicro"
    actions:
      - approve
      - assign_hostgroup: "ceph-mon-nodes"
```

**Manual Review Required:**
- Mismatched hardware (expected vs actual)
- Unknown disk configuration
- Firmware version mismatches
- Failed SMART tests

---

### APPROVED
**Description**: Node cleared for provisioning, ready for OS installation.

**Characteristics:**
- Hostgroup assigned (defines OS, network, partitioning)
- Hostname assigned (DNS naming scheme)
- Network configuration determined
- Partition layout selected

**Hostname Assignment:**
```python
# Example naming scheme
def generate_hostname(facts, hostgroup):
    """
    ceph-osd-r07-u12  (rack 7, u12, OSD role)
    ceph-mon-r03-u05  (rack 3, u05, MON role)
    """
    role = hostgroup.split('-')[1]  # osd, mon, mgr
    rack = determine_rack(facts['ipmi']['ip'])
    u_position = facts.get('chassis_position', 'unk')

    return f"ceph-{role}-r{rack:02d}-u{u_position:02d}"
```

**Build Parameters Set:**
- Debian version (e.g., Debian 12 Bookworm)
- Preseed template
- Root password (encrypted)
- SSH keys
- Network bonds/VLANs
- Post-install scripts

---

### PROVISIONING
**Description**: OS installation actively running via PXE.

**Installation Flow:**

1. **IPMI Power Cycle**
   ```bash
   ipmitool -I lanplus -H $IPMI_IP -U $USER -P $PASS \
     chassis bootdev pxe options=persistent
   ipmitool -I lanplus -H $IPMI_IP -U $USER -P $PASS \
     power reset
   ```

2. **PXE Boot**
   - DHCP provides IP and boot server
   - TFTP serves pxelinux.0
   - Load Debian installer kernel + initrd

3. **Preseed Automated Install**
   - Download preseed from Foreman
   - Partition disks per template
   - Install base packages
   - Configure network
   - Install SSH keys
   - Run post-install scripts

4. **First Boot**
   - Boot from local disk
   - Run Foreman finish script (callback)
   - Install Puppet/Ansible agent
   - Register with Foreman

**Monitoring:**
- Serial-over-LAN capture logs
- Installation webhook callbacks
- Timeout: 45 minutes

**Failure Handling:**
- Installation timeout  PROVISION_FAILED
- Kernel panic  log SOL, mark failed
- Network issues  retry or manual intervention

---

### PROVISIONED
**Description**: OS installed, system booted, base checks passed.

**Verification:**
- SSH responds on management IP
- Foreman finish script callback received
- Basic packages installed
- Root filesystem mounted
- Network interfaces up

**Foreman Callback:**
```bash
# /etc/rc.local or systemd unit (one-shot)
curl -k -X POST https://foreman.example.com/unattended/built \
  -H "Content-Type: application/json" \
  -d '{"token": "'$BUILD_TOKEN'"}'
```

**Next Action:**
- Trigger Ansible configuration workflow
- Transition to CONFIGURING

---

### CONFIGURING
**Description**: Ansible applying Ceph-ready node configuration.

**Ansible Playbook: `ceph_node_baseline.yml`**

Tasks:
1. **System Configuration**
   - Set hostname
   - Configure /etc/hosts
   - Set timezone (UTC)
   - Configure NTP (chrony)
   - Disable SELinux/AppArmor (if required by Ceph)

2. **Network Configuration**
   - Bond management NICs (bond0)
   - Configure cluster network (10G interfaces)
   - Set MTU 9000 for cluster network
   - Disable NetworkManager
   - Configure static routes

3. **Kernel Tuning**
   - Apply sysctl parameters (detailed in Ceph-ready doc)
   - Set I/O schedulers (mq-deadline for SSD, none for NVMe)
   - IRQ affinity tuning
   - Disable transparent huge pages

4. **Storage Preparation**
   - Verify data disks present
   - Do NOT partition (left for Ceph OSD creation)
   - Verify SSD journal devices

5. **Monitoring Agent Installation**
   - Install Prometheus node_exporter
   - Install Telegraf (optional)
   - Configure log forwarding (rsyslog/journald)

6. **Security Hardening**
   - Configure firewall (iptables/nftables)
   - Install fail2ban
   - Harden SSH config
   - Install auditd

**Duration:** 10-15 minutes

**Failure Handling:**
- Ansible failure  CONFIG_FAILED
- Partial success  manual remediation
- Idempotent retry allowed

---

### CONFIGURED
**Description**: Ceph-ready configuration applied successfully.

**Verification:**
- Ansible playbook exit code 0
- All tasks marked 'ok' or 'changed'
- No failed tasks

**Automatic Transition:**
- Trigger validation workflow
- Move to VALIDATING

---

### VALIDATING
**Description**: Running automated health checks and validation tests.

**Validation Test Suite:**

**1. Hardware Tests**
```bash
# Verify expected disk count
lsblk -d -o NAME,SIZE,TYPE | grep disk | wc -l

# Check SMART status all disks
for disk in /dev/sd{a..z}; do
  [ -b "$disk" ] && smartctl -H $disk || true
done

# Verify memory size
free -g | awk '/Mem:/ {print $2}'

# Check CPU count
nproc
```

**2. Network Tests**
```bash
# Ping default gateway
ping -c 3 10.10.0.1

# Verify cluster network MTU
ip link show | grep -A1 "10000.*UP"

# Test bandwidth to other nodes (iperf3)
iperf3 -c ceph-osd-r07-u13 -t 10

# Verify name resolution
getent hosts ceph-mon-r03-u05
```

**3. Storage Tests**
```bash
# Verify no mounted data disks
mount | grep -v "/dev/sda" | grep -v tmpfs

# Check I/O scheduler
cat /sys/block/sdb/queue/scheduler

# Quick write test to SSD
dd if=/dev/zero of=/tmp/test bs=1G count=1 oflag=direct
```

**4. System Tests**
```bash
# Verify NTP sync
chronyc tracking | grep "Leap status.*Normal"

# Check kernel parameters
sysctl -a | grep "vm.swappiness.*10"

# Verify services running
systemctl is-active node_exporter
systemctl is-active sshd
```

**5. Security Tests**
```bash
# Verify SSH keys installed
ssh -o PasswordAuthentication=no localhost echo "OK"

# Check firewall rules loaded
iptables -L -n | grep -q "Chain INPUT"

# Verify audit daemon running
systemctl is-active auditd
```

**Validation Result:**
```json
{
  "node": "ceph-osd-r07-u12",
  "timestamp": "2026-03-18T10:30:00Z",
  "tests": {
    "hardware": {"status": "pass", "score": 100},
    "network": {"status": "pass", "score": 100},
    "storage": {"status": "pass", "score": 100},
    "system": {"status": "pass", "score": 100},
    "security": {"status": "pass", "score": 100}
  },
  "overall": "PASS"
}
```

**Failure Handling:**
- Any test failure  VALIDATION_FAILED
- Store detailed test logs
- Alert operations team
- Allow manual override after review

---

### VALIDATED
**Description**: All validation tests passed, node proven healthy.

**Characteristics:**
- Hardware verified working
- Network connectivity confirmed
- Storage subsystem ready
- Security baseline met
- Monitoring active

**Automatic Transition:**
- Mark node READY_CEPH
- Add to Ceph deployment inventory

---

### READY_CEPH
**Description**: Node available for Ceph cluster deployment.

**Inventory Export:**

Foreman generates dynamic Ansible inventory for ceph-ansible:

```ini
# /etc/ansible/inventory/ceph_cluster
[mons]
ceph-mon-r03-u05 ansible_host=10.10.3.5
ceph-mon-r05-u07 ansible_host=10.10.5.7
ceph-mon-r08-u10 ansible_host=10.10.8.10

[osds]
ceph-osd-r07-u12 ansible_host=10.10.7.12
ceph-osd-r07-u13 ansible_host=10.10.7.13
# ... 500 more OSD nodes

[mgrs]
ceph-mgr-r03-u06 ansible_host=10.10.3.6
ceph-mgr-r05-u08 ansible_host=10.10.5.8

[grafana-server]
ceph-mon-r03-u05

[all:vars]
ansible_user=root
ansible_ssh_private_key_file=/root/.ssh/ceph_deploy
monitor_interface=bond0
public_network=10.10.0.0/16
cluster_network=10.20.0.0/16
osd_auto_discovery=true
osd_objectstore=bluestore
```

**Node Metadata:**
```yaml
# Foreman host parameter: ceph_node_config
disks:
  os_disk: /dev/sda
  journal_device: /dev/nvme0n1
  data_disks:
    - /dev/sdb
    - /dev/sdc
    - /dev/sdd
    # ...
networks:
  management: 10.10.7.12/16
  public: 10.10.7.12/16
  cluster: 10.20.7.12/16
role: osd
```

**Holding Pattern:**
- Node remains in READY_CEPH until Ceph deployment
- Monitoring continues
- Can be re-validated periodically
- Available for immediate deployment

---

### IN_SERVICE
**Description**: Node is active member of Ceph cluster.

**Characteristics:**
- Ceph OSD/MON/MGR daemon running
- Participating in data storage/retrieval
- Monitored by Ceph health checks
- Part of production workload

**Foreman Updates:**
- Status updated via webhook from Ceph monitoring
- Ceph version recorded
- OSD IDs recorded
- Cluster membership confirmed

**Lifecycle in IN_SERVICE:**
- Normal operations
- Monitoring and alerting
- Periodic revalidation (quarterly)
- Firmware updates (scheduled maintenance)

---

### DECOMMISSION
**Description**: Node being removed from cluster (maintenance, replacement, retirement).

**Decommission Workflow:**

1. **Ceph Cluster Removal**
   ```bash
   # Mark OSD out
   ceph osd out osd.42

   # Wait for data migration
   watch ceph -s

   # Stop OSD daemon
   systemctl stop ceph-osd@42

   # Remove OSD from cluster
   ceph osd purge osd.42 --yes-i-really-mean-it
   ```

2. **Foreman State Update**
   - Mark node as DECOMMISSION
   - Remove from monitoring
   - Disable Ansible runs

3. **Data Verification**
   - Confirm no PGs remain on node
   - Verify data replicated to other OSDs

4. **Physical Preparation**
   - Secure erase disks (if policy requires)
   - Document removal in CMDB

**Duration:** Hours to days (depends on data volume)

---

### DECOMMISSIONED
**Description**: Node removed from cluster, ready for physical work or reprovisioning.

**Next Steps:**
- **Reprovision**: Reset to NEW state, restart lifecycle
- **Hardware replacement**: Swap failed components, restart lifecycle
- **Retire**: Physical removal from datacenter

**Audit Trail:**
- Decommission date
- Reason code (upgrade, failure, capacity reduction)
- Approver
- Data migration completion timestamp

---

## Error States

### DISCOVERY_FAILED
**Causes:**
- IPMI boot failure
- Network issues during discovery
- Hardware fault preventing inspection
- Timeout waiting for facts

**Recovery:**
```bash
# Manual retry
foreman-cli host discovery-reboot $HOST_ID

# Or re-register
foreman-cli host delete $HOST_ID
# Restart from NEW
```

### PROVISION_FAILED
**Causes:**
- Preseed errors
- Disk partitioning failure
- Network timeout during install
- Package installation errors

**Recovery:**
1. Review installation logs (serial-over-LAN)
2. Fix underlying issue (bad disk, network config)
3. Retry provision

### CONFIG_FAILED
**Causes:**
- Ansible playbook failure
- Network configuration errors
- Package installation issues
- Service startup failures

**Recovery:**
1. Review Ansible logs
2. SSH to node for manual investigation
3. Fix issue, re-run Ansible
4. Transition back to CONFIGURING

### VALIDATION_FAILED
**Causes:**
- Hardware test failures (SMART errors)
- Network connectivity issues
- Performance below threshold
- Security baseline violations

**Recovery:**
1. Review validation test results
2. Manual investigation
3. Fix underlying issue
4. Re-run validation
5. Manual override if acceptable risk

---

## State Transition Automation

### Foreman Webhooks

Configure webhooks to trigger Ansible Tower/AWX workflows:

```json
{
  "event": "host.provision_complete",
  "webhook_url": "https://awx.example.com/api/v2/job_templates/42/launch/",
  "headers": {
    "Authorization": "Bearer $AWX_TOKEN"
  },
  "payload": {
    "extra_vars": {
      "foreman_host": "{{ host.name }}",
      "foreman_ip": "{{ host.ip }}",
      "hostgroup": "{{ host.hostgroup }}",
      "foreman_id": "{{ host.id }}"
    }
  }
}
```

### State Persistence

Store state in Foreman host parameters:

```yaml
# Host parameter: lifecycle_state
lifecycle_state:
  current: "READY_CEPH"
  previous: "VALIDATED"
  updated_at: "2026-03-18T10:30:00Z"
  history:
    - state: "NEW"
      timestamp: "2026-03-18T09:00:00Z"
    - state: "DISCOVERING"
      timestamp: "2026-03-18T09:05:00Z"
    - state: "DISCOVERED"
      timestamp: "2026-03-18T09:15:00Z"
    # ... full history
```

### Prometheus Metrics

Export lifecycle metrics:

```prometheus
# Nodes by state
node_lifecycle_state{state="READY_CEPH"} 487
node_lifecycle_state{state="IN_SERVICE"} 512
node_lifecycle_state{state="PROVISIONING"} 3
node_lifecycle_state{state="DISCOVERING"} 1

# Transition duration
node_lifecycle_transition_duration_seconds{from="PROVISIONED",to="CONFIGURED"} 780

# Failure rates
node_lifecycle_failures_total{state="PROVISION_FAILED"} 12
node_lifecycle_failures_total{state="VALIDATION_FAILED"} 5
```

---

## Operational Workflows

### Mass Provisioning (100 nodes)

```bash
# Batch 1: Racks 7-9 (33 nodes)
foreman-cli host bulk-action --search "hostgroup=ceph-osd-nodes AND \
  rack~'r0[7-9]' AND lifecycle_state=APPROVED" --action build

# Wait for batch completion (monitor)
watch "foreman-cli host list --search 'lifecycle_state=PROVISIONING' | wc -l"

# Batch 2: Racks 10-12
# ... continue
```

### Emergency Replacement

```bash
# Node failed with bad disk
# 1. Decommission from Ceph (separate runbook)
# 2. Update Foreman state
foreman-cli host update --id $HOST_ID --parameter lifecycle_state=DECOMMISSIONED

# 3. Replace hardware
# 4. Reset to NEW
foreman-cli host delete $HOST_ID
# Physical: replace disk, reboot

# 5. Lifecycle restarts automatically
```

### Firmware Update Workflow

```bash
# Select nodes for firmware update
NODES=$(foreman-cli host list --search "lifecycle_state=IN_SERVICE AND \
  firmware_version='3.76' AND rack='r07'" --fields name)

# For each node:
#  1. Decommission from Ceph (graceful OSD out)
#  2. Update firmware via IPMI
#  3. Re-provision
#  4. Re-deploy Ceph
```

---

## Summary

This lifecycle model provides:

1. **Clear state definitions** - No ambiguity about node status
2. **Automated transitions** - Minimal manual intervention
3. **Error handling** - Recovery paths for every failure mode
4. **Auditability** - Complete history of node journey
5. **Scalability** - Handles 1000+ nodes with batch operations
6. **Integration** - Foreman, Ansible, Ceph workflows connected
7. **Observability** - Metrics and monitoring at every stage

**Next**: Design the network boot infrastructure to support this lifecycle.
