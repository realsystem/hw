# Ceph-Ready Node Configuration

## Overview

Production-grade system configuration optimizing Debian nodes for Ceph storage cluster deployment, covering network tuning, kernel parameters, storage optimization, and performance settings.

---

## Network Configuration

### Multi-Network Design

**Ceph Network Requirements:**

```
┌────────────────────────────────────────────────────────────┐
│              Ceph Node - Network Interfaces                 │
├────────────────────────────────────────────────────────────┤
│                                                             │
│  Management Network (VLAN 10, bond0)                       │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ bond0: 10.10.7.12/16 (eth0 + eth1)                   │  │
│  │ - SSH access                                          │  │
│  │ - Ansible communication                               │  │
│  │ - Foreman callbacks                                   │  │
│  │ - Monitoring (Prometheus, Grafana)                    │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                             │
│  Ceph Public Network (VLAN 20, bond1)                      │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ bond1: 10.20.7.12/16 (eth2 + eth3)                   │  │
│  │ - Client traffic (RBD, RGW, CephFS)                  │  │
│  │ - Monitor communication                               │  │
│  │ - MTU 9000 (Jumbo frames)                            │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                             │
│  Ceph Cluster Network (VLAN 30, dedicated)                 │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ eth4: 10.30.7.12/16 (dedicated 10GbE)                │  │
│  │ - OSD replication                                     │  │
│  │ - OSD recovery                                        │  │
│  │ - Heartbeat                                           │  │
│  │ - MTU 9000 (Jumbo frames)                            │  │
│  │ - Highest priority traffic                           │  │
│  └─────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

### Network Interface Configuration

**/etc/network/interfaces:**
```bash
# Loopback
auto lo
iface lo inet loopback

# Management Network - Bond (Active-Backup)
auto bond0
iface bond0 inet static
    address 10.10.7.12
    netmask 255.255.0.0
    gateway 10.10.0.1
    dns-nameservers 10.5.0.1 10.5.0.2
    dns-search example.com
    bond-slaves eth0 eth1
    bond-mode active-backup
    bond-miimon 100
    bond-downdelay 200
    bond-updelay 200
    bond-primary eth0
    mtu 1500

# Ceph Public Network - Bond (802.3ad LACP)
auto bond1
iface bond1 inet static
    address 10.20.7.12
    netmask 255.255.0.0
    bond-slaves eth2 eth3
    bond-mode 802.3ad
    bond-miimon 100
    bond-downdelay 200
    bond-updelay 200
    bond-lacp-rate fast
    bond-xmit-hash-policy layer3+4
    mtu 9000
    post-up ip route add 10.20.0.0/16 dev bond1 src 10.20.7.12 table 100
    post-up ip rule add from 10.20.7.12 table 100

# Ceph Cluster Network - Dedicated (No Bond)
auto eth4
iface eth4 inet static
    address 10.30.7.12
    netmask 255.255.0.0
    mtu 9000
    post-up ethtool -G eth4 rx 4096 tx 4096
    post-up ethtool -K eth4 tso on gso on gro on
    post-up ip route add 10.30.0.0/16 dev eth4 src 10.30.7.12 table 200
    post-up ip rule add from 10.30.7.12 table 200
```

### Bonding Configuration

**/etc/modprobe.d/bonding.conf:**
```
alias bond0 bonding
alias bond1 bonding
options bonding max_bonds=2 miimon=100
```

### Network Tuning (sysctl)

**/etc/sysctl.d/90-ceph-network.conf:**
```ini
# TCP/IP Stack Tuning for Ceph

# Increase TCP buffer sizes (10GbE optimization)
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# Increase network device backlog
net.core.netdev_max_backlog = 300000
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 8000

# TCP congestion control (HTCP recommended for Ceph)
net.ipv4.tcp_congestion_control = htcp

# Enable TCP window scaling
net.ipv4.tcp_window_scaling = 1

# Increase max connections
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192

# TCP keepalive tuning
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# Fast socket recycling (be cautious in NAT environments)
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# MTU probing (for Jumbo frame negotiation)
net.ipv4.tcp_mtu_probing = 1

# Disable TCP slow start after idle
net.ipv4.tcp_slow_start_after_idle = 0

# IP local port range (for many connections)
net.ipv4.ip_local_port_range = 10000 65535

# Increase max tracked connections
net.netfilter.nf_conntrack_max = 1048576

# Timestamps and SACK
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# Disable ICMP redirect acceptance (security)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Disable source packet routing (security)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
```

### NIC Driver Optimization

**Intel X520/X540 10GbE:**
```bash
# /etc/modprobe.d/ixgbe.conf
options ixgbe InterruptThrottleRate=1,1,1,1
options ixgbe RSS=16,16,16,16
options ixgbe MQ=1,1,1,1
options ixgbe VMDQ=0,0,0,0
```

**Mellanox ConnectX-3/4:**
```bash
# /etc/modprobe.d/mlx4.conf
options mlx4_core log_num_mgm_entry_size=-1
options mlx4_en inline_thold=128
```

---

## Kernel Parameters

### System-Wide Tuning

**/etc/sysctl.d/90-ceph-kernel.conf:**
```ini
# Memory Management
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 5
vm.dirty_writeback_centisecs = 500
vm.dirty_expire_centisecs = 3000
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 1048576

# Huge Pages (Disable THP - Ceph recommendation)
# Set via systemd service (shown below)

# File Descriptors
fs.file-max = 2097152
fs.aio-max-nr = 1048576

# Process/Thread Limits
kernel.pid_max = 4194303
kernel.threads-max = 2097152

# Shared Memory
kernel.shmmax = 68719476736
kernel.shmall = 4294967296

# Core Dumps (disable for production)
kernel.core_uses_pid = 1
kernel.core_pattern = /var/crash/core.%e.%p.%h.%t
fs.suid_dumpable = 2

# Security
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
```

### Disable Transparent Huge Pages

**Systemd Service:**
```ini
# /etc/systemd/system/disable-thp.service
[Unit]
Description=Disable Transparent Huge Pages (THP)
After=sysinit.target local-fs.target
Before=ceph-osd.target ceph-mon.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**Enable:**
```bash
systemctl daemon-reload
systemctl enable disable-thp.service
systemctl start disable-thp.service

# Verify
cat /sys/kernel/mm/transparent_hugepage/enabled
# Should show: always madvise [never]
```

---

## Storage Configuration

### I/O Scheduler Tuning

**Rationale:**
- **SSD/NVMe**: `none` (no scheduling, direct to device)
- **HDD**: `mq-deadline` (elevator for rotational media)

**Udev Rule:**
```bash
# /etc/udev/rules.d/60-ceph-io-scheduler.rules

# NVMe - no scheduler
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"

# SSD - no scheduler (check rotational flag)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"

# HDD - mq-deadline
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
```

**Apply:**
```bash
udevadm control --reload-rules
udevadm trigger
```

**Verification:**
```bash
for disk in /sys/block/sd*/queue/scheduler; do
    echo "$disk: $(cat $disk)"
done

# Expected:
# /sys/block/sda/queue/scheduler: [mq-deadline] none  (OS disk, SSD)
# /sys/block/sdb/queue/scheduler: [mq-deadline] none  (Data disk, HDD)
# /sys/block/nvme0n1/queue/scheduler: [none]          (NVMe)
```

### Disk Read-Ahead

**Increase for large sequential reads (Ceph recovery):**
```bash
# /etc/udev/rules.d/60-ceph-readahead.rules

# Set read-ahead to 8MB for data disks
ACTION=="add|change", KERNEL=="sd[b-z]", ATTR{bdi/read_ahead_kb}="8192"
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{bdi/read_ahead_kb}="8192"
```

### Block Device Queue Depth

**Increase for NVMe and high-performance SSD:**
```bash
# /etc/udev/rules.d/60-ceph-queue-depth.rules

# NVMe queue depth
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/nr_requests}="1024"

# SSD queue depth
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/nr_requests}="512"
```

---

## CPU and IRQ Tuning

### CPU Governor

**Set to `performance` for consistent latency:**
```bash
# /etc/default/cpufrequtils
GOVERNOR="performance"
```

**Or via systemd:**
```bash
# /etc/systemd/system/cpu-governor.service
[Unit]
Description=Set CPU governor to performance
After=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

### IRQ Balancing

**Install and configure irqbalance:**
```bash
apt-get install irqbalance

# /etc/default/irqbalance
ENABLED="1"
IRQBALANCE_BANNED_CPUS="0,1"  # Reserve CPU 0-1 for OS tasks
IRQBALANCE_ARGS="--policyscript=/usr/local/bin/irq-policy.sh"
```

**IRQ Affinity for Network Cards:**
```bash
#!/bin/bash
# /usr/local/bin/set-irq-affinity.sh <interface> <cpu_list>

IFACE=$1
CPU_LIST=$2

# Get IRQ numbers for interface
IRQS=$(grep $IFACE /proc/interrupts | awk '{print $1}' | sed 's/://')

for irq in $IRQS; do
    echo $CPU_LIST > /proc/irq/$irq/smp_affinity_list
done

echo "IRQ affinity set for $IFACE to CPUs $CPU_LIST"
```

**Example: Pin 10GbE NICs to specific CPUs:**
```bash
# Ceph public network (eth2-eth3) -> CPU 2-9
/usr/local/bin/set-irq-affinity.sh eth2 2-9
/usr/local/bin/set-irq-affinity.sh eth3 2-9

# Ceph cluster network (eth4) -> CPU 10-17
/usr/local/bin/set-irq-affinity.sh eth4 10-17
```

### NUMA Awareness

**Check NUMA topology:**
```bash
numactl --hardware
lscpu | grep NUMA
```

**Pin OSD processes to NUMA nodes (handled by Ceph deployment):**
```yaml
# ceph.conf (set during ceph-ansible deployment)
[osd]
osd_numa_node = -1  # Auto-detect, or specify node
```

---

## Time Synchronization

### Chrony Configuration

**Ceph requires tight time sync (±50ms):**

**/etc/chrony/chrony.conf:**
```
# NTP servers (prefer local stratum 1 servers)
server ntp1.example.com iburst prefer
server ntp2.example.com iburst
server ntp3.example.com iburst

# Allow drift up to 1 second (adjust as needed)
makestep 1.0 3

# Enable NTS (Network Time Security) if supported
# nts ntp1.example.com

# Increase logging
logdir /var/log/chrony
log measurements statistics tracking

# Harden security
bindcmdaddress ::1
bindcmdaddress 127.0.0.1
cmdallow 127.0.0.1

# Leap second handling
leapsectz right/UTC
```

**Monitoring:**
```bash
# Check sync status
chronyc tracking

# Expected output:
# Leap status     : Normal
# Stratum         : 2
# Ref time (UTC)  : Wed Mar 18 10:30:00 2026
# System time     : 0.000001234 seconds slow of NTP time
# Last offset     : -0.000000123 seconds
# RMS offset      : 0.000005678 seconds
```

**Alerting:**
```bash
# Monitor clock offset
OFFSET=$(chronyc tracking | grep "System time" | awk '{print $4}')
if (( $(echo "$OFFSET > 0.05" | bc -l) )); then
    echo "WARNING: Clock offset ${OFFSET}s exceeds threshold"
    # Send alert
fi
```

---

## Firewall Configuration

### iptables Rules for Ceph

**/etc/iptables/rules.v4:**
```bash
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Loopback
-A INPUT -i lo -j ACCEPT

# Established connections
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# SSH (management network only)
-A INPUT -i bond0 -p tcp --dport 22 -j ACCEPT

# Monitoring (Prometheus node_exporter)
-A INPUT -i bond0 -p tcp --dport 9100 -j ACCEPT

# Ceph Monitor (public network)
-A INPUT -i bond1 -p tcp --dport 6789 -j ACCEPT
-A INPUT -i bond1 -p tcp --dport 3300 -j ACCEPT  # msgr2

# Ceph Manager
-A INPUT -i bond1 -p tcp --dport 8443 -j ACCEPT  # mgr dashboard
-A INPUT -i bond1 -p tcp --dport 9283 -j ACCEPT  # mgr prometheus

# Ceph OSD (public network)
-A INPUT -i bond1 -p tcp --dport 6800:7300 -j ACCEPT

# Ceph OSD (cluster network - full access)
-A INPUT -i eth4 -j ACCEPT

# ICMP (ping)
-A INPUT -p icmp -j ACCEPT

# Reject all other
-A INPUT -j REJECT --reject-with icmp-host-prohibited

COMMIT
```

**Apply:**
```bash
apt-get install iptables-persistent
systemctl enable netfilter-persistent
netfilter-persistent save
netfilter-persistent reload
```

---

## Monitoring Agent Installation

### Prometheus Node Exporter

```bash
apt-get install prometheus-node-exporter

systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

# Verify
curl http://localhost:9100/metrics | grep node_
```

### Custom Ceph Collectors

```bash
# /usr/local/bin/ceph_disk_exporter.sh
#!/bin/bash

# Expose disk metrics for Prometheus
while true; do
    echo "# HELP ceph_disk_smart_health SMART health status (0=PASSED, 1=FAILED)"
    echo "# TYPE ceph_disk_smart_health gauge"

    for disk in /dev/sd{b..z}; do
        [ -b "$disk" ] || continue
        HEALTH=$(smartctl -H $disk | grep "SMART overall-health" | awk '{print $NF}')
        if [ "$HEALTH" == "PASSED" ]; then
            echo "ceph_disk_smart_health{device=\"$disk\"} 0"
        else
            echo "ceph_disk_smart_health{device=\"$disk\"} 1"
        fi
    done

    sleep 300  # Update every 5 minutes
done
```

---

## Ansible Playbook: Ceph-Ready Configuration

```yaml
# roles/ceph_node_baseline/tasks/main.yml
---
- name: Install required packages
  apt:
    name:
      - chrony
      - prometheus-node-exporter
      - smartmontools
      - nvme-cli
      - sysstat
      - iotop
      - irqbalance
      - tuned
    state: present
    update_cache: yes

- name: Configure network interfaces
  template:
    src: interfaces.j2
    dest: /etc/network/interfaces
    owner: root
    group: root
    mode: '0644'
  notify: restart networking

- name: Apply sysctl parameters
  sysctl:
    name: "{{ item.key }}"
    value: "{{ item.value }}"
    state: present
    reload: yes
  loop: "{{ ceph_sysctl_params | dict2items }}"

- name: Install disable-thp systemd service
  copy:
    src: disable-thp.service
    dest: /etc/systemd/system/disable-thp.service
    owner: root
    group: root
    mode: '0644'
  notify:
    - systemd daemon-reload
    - enable disable-thp

- name: Configure udev rules for I/O scheduler
  copy:
    src: 60-ceph-io-scheduler.rules
    dest: /etc/udev/rules.d/60-ceph-io-scheduler.rules
    owner: root
    group: root
    mode: '0644'
  notify: reload udev

- name: Configure chrony
  template:
    src: chrony.conf.j2
    dest: /etc/chrony/chrony.conf
    owner: root
    group: root
    mode: '0644'
  notify: restart chrony

- name: Set CPU governor to performance
  copy:
    src: cpu-governor.service
    dest: /etc/systemd/system/cpu-governor.service
    owner: root
    group: root
    mode: '0644'
  notify:
    - systemd daemon-reload
    - enable cpu-governor

- name: Configure firewall
  template:
    src: iptables-rules.v4.j2
    dest: /etc/iptables/rules.v4
    owner: root
    group: root
    mode: '0644'
  notify: reload iptables

- name: Enable and start monitoring
  systemd:
    name: prometheus-node-exporter
    enabled: yes
    state: started
```

---

## Validation Tests

### Post-Configuration Validation Script

```bash
#!/bin/bash
# /usr/local/bin/validate-ceph-ready.sh

ERRORS=0

echo "=== Ceph-Ready Node Validation ==="

# 1. Network configuration
echo "Checking network interfaces..."
for iface in bond0 bond1 eth4; do
    if ! ip link show $iface &>/dev/null; then
        echo " Interface $iface not found"
        ERRORS=$((ERRORS + 1))
    fi
done

# MTU check
MTU_BOND1=$(ip link show bond1 | grep mtu | awk '{print $5}')
if [ "$MTU_BOND1" != "9000" ]; then
    echo " bond1 MTU is $MTU_BOND1 (expected 9000)"
    ERRORS=$((ERRORS + 1))
fi

# 2. Sysctl parameters
echo "Checking sysctl parameters..."
CHECKS=(
    "vm.swappiness:10"
    "net.core.rmem_max:134217728"
    "net.ipv4.tcp_congestion_control:htcp"
)
for check in "${CHECKS[@]}"; do
    key=$(echo $check | cut -d: -f1)
    expected=$(echo $check | cut -d: -f2)
    actual=$(sysctl -n $key)
    if [ "$actual" != "$expected" ]; then
        echo " $key = $actual (expected $expected)"
        ERRORS=$((ERRORS + 1))
    fi
done

# 3. Transparent Huge Pages
THP=$(cat /sys/kernel/mm/transparent_hugepage/enabled)
if [[ ! "$THP" =~ "never" ]]; then
    echo " THP not disabled: $THP"
    ERRORS=$((ERRORS + 1))
fi

# 4. I/O Schedulers
echo "Checking I/O schedulers..."
for disk in /sys/block/sd*/queue/scheduler; do
    sched=$(cat $disk)
    if [[ "$sched" =~ "mq-deadline" ]] || [[ "$sched" =~ "none" ]]; then
        :  # OK
    else
        echo " Unexpected scheduler: $disk = $sched"
        ERRORS=$((ERRORS + 1))
    fi
done

# 5. Time synchronization
echo "Checking time sync..."
chronyc tracking | grep -q "Leap status.*Normal"
if [ $? -ne 0 ]; then
    echo " chrony not synchronized"
    ERRORS=$((ERRORS + 1))
fi

# 6. Services
SERVICES=("chrony" "prometheus-node-exporter" "irqbalance")
for svc in "${SERVICES[@]}"; do
    if ! systemctl is-active --quiet $svc; then
        echo " Service $svc not running"
        ERRORS=$((ERRORS + 1))
    fi
done

# 7. Firewall
if ! iptables -L -n | grep -q "Chain INPUT"; then
    echo " Firewall not configured"
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo " Ceph-ready validation PASSED"
    exit 0
else
    echo " Ceph-ready validation FAILED ($ERRORS errors)"
    exit 1
fi
```

---

## Summary

This Ceph-ready configuration provides:

1. **Network Optimization**: Multi-network design, bonding, jumbo frames, TCP tuning
2. **Kernel Tuning**: Memory management, file descriptors, security
3. **Storage Optimization**: I/O schedulers, read-ahead, queue depth
4. **CPU/IRQ Tuning**: Performance governor, IRQ affinity, NUMA awareness
5. **Time Sync**: Precise chrony configuration for Ceph
6. **Security**: Firewall rules, hardening parameters
7. **Monitoring**: Node exporter, custom collectors
8. **Automation**: Ansible playbooks, validation scripts

**Next**: Observability stack (monitoring, logging, alerting).
