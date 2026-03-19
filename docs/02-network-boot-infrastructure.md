# Network Boot Infrastructure Design

## Overview

A highly-available, scalable PXE boot infrastructure supporting simultaneous provisioning of 100+ nodes with resilience against single points of failure.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      FOREMAN CONTROL PLANE (HA)                          │
│  ┌──────────────────────┐         ┌──────────────────────┐             │
│  │   Foreman Server 1    │         │   Foreman Server 2    │             │
│  │   (Active)            │◄───────►│   (Standby)           │             │
│  │                       │         │                       │             │
│  │  - Web UI/API         │         │  - Web UI/API         │             │
│  │  - Template Engine    │         │  - Template Engine    │             │
│  │  - Orchestration      │         │  - Orchestration      │             │
│  └───────────┬───────────┘         └───────────┬───────────┘             │
│              │                                  │                         │
│              │  ┌───────────────────────────────┴────────────────┐       │
│              └─►│  PostgreSQL (Patroni Cluster)                  │       │
│                 │  ┌──────────┐  ┌──────────┐  ┌──────────┐     │       │
│                 │  │ Primary  │◄─┤ Standby  │◄─┤ Standby  │     │       │
│                 │  │  Node    │  │  Node    │  │  Node    │     │       │
│                 │  └──────────┘  └──────────┘  └──────────┘     │       │
│                 │  HAProxy + Keepalived (VIP: 10.10.0.10)        │       │
│                 └────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────┘
                                     │
                                     │ Smart Proxy API
                                     │
          ┌──────────────────────────┼──────────────────────────┐
          │                          │                          │
┌─────────▼──────────┐    ┌──────────▼─────────┐    ┌──────────▼─────────┐
│  Smart Proxy       │    │  Smart Proxy       │    │  Smart Proxy       │
│  Rack 3-5          │    │  Rack 6-9          │    │  Rack 10-12        │
│  (10.10.0.11)      │    │  (10.10.0.12)      │    │  (10.10.0.13)      │
│                    │    │                    │    │                    │
│  ┌──────────────┐  │    │  ┌──────────────┐  │    │  ┌──────────────┐  │
│  │ DHCP Server  │  │    │  │ DHCP Server  │  │    │  │ DHCP Server  │  │
│  │ (dnsmasq)    │  │    │  │ (dnsmasq)    │  │    │  │ (dnsmasq)    │  │
│  │              │  │    │  │              │  │    │  │              │  │
│  │ Scope:       │  │    │  │ Scope:       │  │    │  │ Scope:       │  │
│  │ 10.50.3.0/22 │  │    │  │ 10.50.6.0/22 │  │    │  │ 10.50.10.0/22│  │
│  └──────────────┘  │    │  └──────────────┘  │    │  └──────────────┘  │
│                    │    │                    │    │                    │
│  ┌──────────────┐  │    │  ┌──────────────┐  │    │  ┌──────────────┐  │
│  │ TFTP Server  │  │    │  │ TFTP Server  │  │    │  │ TFTP Server  │  │
│  │ (tftp-hpa)   │  │    │  │ (tftp-hpa)   │  │    │  │ (tftp-hpa)   │  │
│  │              │  │    │  │              │  │    │  │              │  │
│  │ Boot files:  │  │    │  │ Boot files:  │  │    │  │ Boot files:  │  │
│  │ - pxelinux   │  │    │  │ - pxelinux   │  │    │  │ - pxelinux   │  │
│  │ - grub       │  │    │  │ - grub       │  │    │  │ - grub       │  │
│  │ - iPXE       │  │    │  │ - iPXE       │  │    │  │ - iPXE       │  │
│  └──────────────┘  │    │  └──────────────┘  │    │  └──────────────┘  │
│                    │    │                    │    │                    │
│  ┌──────────────┐  │    │  ┌──────────────┐  │    │  ┌──────────────┐  │
│  │ HTTP Server  │  │    │  │ HTTP Server  │  │    │  │ HTTP Server  │  │
│  │ (nginx)      │  │    │  │ (nginx)      │  │    │  │ (nginx)      │  │
│  │              │  │    │  │              │  │    │  │              │  │
│  │ Serves:      │  │    │  │ Serves:      │  │    │  │ Serves:      │  │
│  │ - Kernels    │  │    │  │ - Kernels    │  │    │  │ - Kernels    │  │
│  │ - Initrds    │  │    │  │ - Initrds    │  │    │  │ - Initrds    │  │
│  │ - Preseed    │  │    │  │ - Preseed    │  │    │  │ - Preseed    │  │
│  │ - Packages   │  │    │  │ - Packages   │  │    │  │ - Packages   │  │
│  └──────────────┘  │    │  └──────────────┘  │    │  └──────────────┘  │
│                    │    │                    │    │                    │
│  ┌──────────────┐  │    │  ┌──────────────┐  │    │  ┌──────────────┐  │
│  │ DNS Forwarder│  │    │  │ DNS Forwarder│  │    │  │ DNS Forwarder│  │
│  │ (dnsmasq)    │  │    │  │ (dnsmasq)    │  │    │  │ (dnsmasq)    │  │
│  └──────────────┘  │    │  └──────────────┘  │    │  └──────────────┘  │
└────────┬───────────┘    └────────┬───────────┘    └────────┬───────────┘
         │                         │                         │
         │ Provisioning Network    │                         │
         │ (isolated VLAN)         │                         │
         │                         │                         │
    ┌────▼─────┐              ┌────▼─────┐              ┌────▼─────┐
    │  Servers │              │  Servers │              │  Servers │
    │ Rack 3-5 │              │ Rack 6-9 │              │ Rack 10-12│
    └──────────┘              └──────────┘              └──────────┘


┌────────────────────────────────────────────────────────────────────┐
│              CONTENT DELIVERY (OPTIONAL - PERFORMANCE)              │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Debian Mirror / Pulp Server (Katello)                       │  │
│  │                                                               │  │
│  │  - Local Debian repository mirror                            │  │
│  │  - Reduces external bandwidth                                │  │
│  │  - Faster package installation                               │  │
│  │  - Version pinning for consistency                           │  │
│  │                                                               │  │
│  │  Capacity: 500GB (Debian main + security + updates)          │  │
│  │  Sync: Daily at 02:00 UTC                                    │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

---

## Network Segregation

### Provisioning Network (VLAN 50)
**Purpose**: Isolated network for PXE boot and OS installation

**Characteristics:**
- **Subnet**: 10.50.0.0/16 (65,536 addresses)
- **Isolation**: Separate VLAN, no routing to production
- **DHCP scope**: 10.50.0.100 - 10.50.255.254
- **Gateway**: 10.50.0.1 (firewall, outbound only for package downloads)
- **DNS**: Provided by Smart Proxy (dnsmasq)

**Security:**
- No inbound from production networks
- Outbound allowed to package mirrors only
- After provisioning complete, move to management VLAN

**Design Rationale:**
- Prevent provisioning storms from affecting production
- Contain DHCP traffic to provisioning scope
- Security isolation during vulnerable install phase

### Management Network (VLAN 10)
**Purpose**: Post-provisioning management access

**Characteristics:**
- **Subnet**: 10.10.0.0/16
- **Static IPs**: Assigned during provisioning
- **DNS**: Corporate DNS servers
- **Gateway**: 10.10.0.1

**Usage:**
- SSH access for administration
- Ansible communication
- Foreman agent callbacks
- Monitoring traffic

### Ceph Public Network (VLAN 20)
**Purpose**: Ceph client traffic (RBD, RGW, CephFS)

**Characteristics:**
- **Subnet**: 10.20.0.0/16
- **MTU**: 9000 (Jumbo frames)
- **Bandwidth**: 10 Gbps bonded interfaces

### Ceph Cluster Network (VLAN 30)
**Purpose**: Ceph OSD replication and recovery

**Characteristics:**
- **Subnet**: 10.30.0.0/16
- **MTU**: 9000
- **Bandwidth**: 10 Gbps dedicated interfaces
- **Isolation**: Ceph cluster traffic only

---

## DHCP Architecture

### Distributed DHCP with Failover

**Problem**: Single DHCP server is SPOF for provisioning.

**Solution**: Multiple DHCP servers per rack segment with shared configuration.

### Option 1: Foreman Smart Proxy DHCP (dnsmasq)

**Configuration per Smart Proxy:**

```ini
# /etc/dnsmasq.d/foreman-proxy.conf

# Interface binding
interface=eth0
bind-interfaces

# DHCP scope for this rack segment
dhcp-range=10.50.3.100,10.50.5.254,24h

# Boot options
dhcp-boot=pxelinux.0,foreman-proxy-r3-5,10.10.0.11

# PXE options
dhcp-option=66,10.10.0.11  # TFTP server
dhcp-option=67,pxelinux.0   # Boot filename

# Domain and DNS
domain=provision.internal
dhcp-option=15,provision.internal

# Disable DNS for provisioning network
port=0

# DHCP authoritative
dhcp-authoritative

# Ignore unknown clients (security)
dhcp-ignore=#known

# DHCP host reservations dynamically managed by Foreman
dhcp-hostsfile=/var/lib/foreman-proxy/dhcp/dhcp_hostsfile

# Logging
log-dhcp
log-facility=/var/log/dnsmasq/dnsmasq.log
```

**Foreman Integration:**
```ruby
# /etc/foreman-proxy/settings.d/dhcp.yml
---
:enabled: true
:use_provider: dhcp_isc
:server: 10.10.0.11

# Smart Proxy adds/removes DHCP reservations via API
# When host is approved for provisioning:
#   - Create DHCP reservation (MAC -> IP)
#   - Set boot options (next-server, filename)
# After provisioning complete:
#   - Remove DHCP reservation
```

**DHCP Reservation Example:**
```
# /var/lib/foreman-proxy/dhcp/dhcp_hostsfile
00:25:90:aa:bb:cc,10.50.3.12,ceph-osd-r03-u12,24h
00:25:90:aa:bb:cd,10.50.3.13,ceph-osd-r03-u13,24h
```

### Option 2: ISC DHCP with Failover

For larger deployments requiring DHCP high availability:

```
# /etc/dhcp/dhcpd.conf (Primary server 10.10.0.11)

failover peer "rack3-5-failover" {
  primary;
  address 10.10.0.11;
  port 647;
  peer address 10.10.0.14;  # Secondary Smart Proxy
  peer port 647;
  max-response-delay 60;
  max-unacked-updates 10;
  load balance max seconds 3;
  mclt 3600;
  split 128;
}

subnet 10.50.3.0 netmask 255.255.252.0 {
  pool {
    failover peer "rack3-5-failover";
    range 10.50.3.100 10.50.5.254;
  }

  option routers 10.50.0.1;
  option domain-name "provision.internal";
  option subnet-mask 255.255.252.0;

  next-server 10.10.0.11;  # TFTP server
  filename "pxelinux.0";
}

# Dynamic updates from Foreman
include "/var/lib/foreman-proxy/dhcp/dhcpd.hosts";
```

**Failover Behavior:**
- Both servers active, split pool 50/50
- If primary fails, secondary serves 100%
- Auto-resync when primary returns
- Shared lease database

---

## TFTP Architecture

### Per-Rack TFTP Servers

**Design**: Each Smart Proxy runs local TFTP server for its rack segment.

**Benefits:**
- Reduces network congestion (local boot file access)
- Survives control plane failure
- Scales horizontally

**Configuration:**
```
# /etc/default/tftpd-hpa

TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot"
TFTP_ADDRESS="10.10.0.11:69"
TFTP_OPTIONS="--secure --verbose"
```

**Directory Structure:**
```
/var/lib/tftpboot/
├── pxelinux.0              # BIOS boot loader
├── lpxelinux.0             # Large PXE (HTTP download support)
├── grub2/
│   ├── grubx64.efi         # UEFI boot loader
│   └── grub.cfg            # Generated by Foreman
├── boot/
│   ├── debian-12-amd64-linux          # Kernel
│   ├── debian-12-amd64-initrd.gz      # Initial ramdisk
│   ├── discovery-image-linux          # Discovery kernel
│   └── discovery-image-initrd.gz      # Discovery initrd
└── pxelinux.cfg/
    ├── default             # Default boot menu
    └── 01-00-25-90-aa-bb-cc  # Per-MAC boot config (from Foreman)
```

**Boot Config Template** (Foreman PXELinux):
```
# pxelinux.cfg/01-00-25-90-aa-bb-cc
DEFAULT linux
LABEL linux
  KERNEL boot/debian-12-amd64-linux
  APPEND initrd=boot/debian-12-amd64-initrd.gz auto=true priority=critical url=http://foreman.example.com/unattended/preseed?token=abc123 netcfg/get_hostname=ceph-osd-r03-u12 locale=en_US console-setup/ask_detect=false keyboard-configuration/xkb-keymap=us netcfg/choose_interface=auto
IPAPPEND 2
```

**UEFI Boot Config** (Foreman Grub2):
```
# grub2/grub.cfg-01-00-25-90-aa-bb-cc
set timeout=10
menuentry 'Install Debian 12' {
  linuxefi boot/debian-12-amd64-linux auto=true priority=critical url=http://foreman.example.com/unattended/preseed?token=abc123
  initrdefi boot/debian-12-amd64-initrd.gz
}
```

### TFTP Replication

**Sync Strategy**: Foreman Smart Proxy automatically syncs boot files from central repository.

**Rsync Cron Job:**
```bash
#!/bin/bash
# /etc/cron.hourly/tftp-sync

rsync -avz --delete \
  rsync://foreman.example.com/tftpboot/ \
  /var/lib/tftpboot/

# Restart TFTP if changes detected
if [ $? -eq 0 ]; then
  systemctl reload tftpd-hpa
fi
```

---

## HTTP Boot Optimization

### Why HTTP for Debian Install?

**Problem with TFTP**:
- Slow (speed limited to ~1 MB/s)
- Unreliable over WAN
- Poor performance with large initrd files (200+ MB)

**Solution**: Use iPXE chain-loading for HTTP boot.

### iPXE Boot Flow

```
Server PXE Request
       │
       ▼
   DHCP Offer
   (next-server: TFTP)
       │
       ▼
   TFTP: ipxe.pxe
   (250 KB, fast)
       │
       ▼
   iPXE Script Load
       │
       ▼
   HTTP Download:
   - Kernel (50 MB)
   - Initrd (250 MB)
   - Preseed
       │
       ▼
   Debian Installer Boots
```

### iPXE Configuration

**DHCP Config for iPXE:**
```
# Detect iPXE client
if exists user-class and option user-class = "iPXE" {
  filename "http://foreman-proxy-r3-5.example.com/ipxe/boot.ipxe";
} else {
  filename "ipxe.pxe";
}
```

**iPXE Script Template** (Foreman):
```perl
#!ipxe
# Generated by Foreman for MAC: 00:25:90:aa:bb:cc

dhcp

kernel http://foreman-proxy-r3-5.example.com/debian/12/kernel auto=true priority=critical url=http://foreman.example.com/unattended/preseed?token=abc123 netcfg/get_hostname=ceph-osd-r03-u12

initrd http://foreman-proxy-r3-5.example.com/debian/12/initrd.gz

boot
```

**Performance Comparison:**
- **TFTP**: Kernel+initrd download: 5-8 minutes
- **HTTP**: Kernel+initrd download: 30-45 seconds

### HTTP Content Caching

**Nginx Configuration:**
```nginx
# /etc/nginx/sites-available/foreman-proxy

server {
    listen 80;
    server_name foreman-proxy-r3-5.example.com;

    # Cache directory
    proxy_cache_path /var/cache/nginx/foreman levels=1:2 keys_zone=foreman_cache:100m max_size=50g inactive=30d use_temp_path=off;

    # Boot files (high cache)
    location /debian/ {
        alias /var/www/foreman/debian/;
        autoindex on;

        # Enable caching
        proxy_cache foreman_cache;
        proxy_cache_valid 200 30d;
        add_header X-Cache-Status $upstream_cache_status;
    }

    # Preseed files (no cache - dynamic)
    location /unattended/ {
        proxy_pass http://foreman.example.com;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # No caching for preseed (contains host-specific config)
        proxy_no_cache 1;
        proxy_cache_bypass 1;
    }

    # Performance tuning
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
}
```

---

## DNS Configuration

### Provisioning DNS (dnsmasq)

**Dual Role**: DHCP + DNS for provisioning network

```ini
# /etc/dnsmasq.d/provisioning-dns.conf

# DNS configuration
domain=provision.internal
expand-hosts

# Upstream DNS (for package mirror resolution)
server=8.8.8.8
server=8.8.4.4

# Local DNS records
address=/foreman.provision.internal/10.10.0.10
address=/foreman-proxy-r3-5.provision.internal/10.10.0.11

# PTR records
ptr-record=10.0.10.10.in-addr.arpa,foreman.provision.internal
```

**Dynamic DNS Updates**:

Foreman Smart Proxy updates DNS when hosts are provisioned:

```bash
# Add A record
dnsmasq --test --add-host=ceph-osd-r03-u12,10.50.3.12

# Add PTR record
dnsmasq --test --add-ptr=10.50.3.12,ceph-osd-r03-u12.provision.internal
```

### Post-Provisioning DNS

After installation, nodes switch to production DNS:

**Preseed Post-Install Script:**
```bash
# /etc/network/interfaces.d/eth0
auto eth0
iface eth0 inet static
    address 10.10.3.12
    netmask 255.255.0.0
    gateway 10.10.0.1
    dns-nameservers 10.5.0.1 10.5.0.2  # Production DNS
    dns-search example.com
```

---

## Provisioning Storm Protection

### Problem

Simultaneously powering on 100 nodes can cause:
- DHCP exhaustion
- TFTP server overload
- Network congestion
- Control plane API saturation

### Rate Limiting Strategy

**Batch Provisioning:**

```python
# Foreman batch provisioning script

import time
import foremanapi

BATCH_SIZE = 20
BATCH_DELAY = 300  # 5 minutes between batches

hosts = foreman.get_hosts(search='hostgroup=ceph-osd-nodes AND build_status=approved')

for batch in chunks(hosts, BATCH_SIZE):
    print(f"Starting batch of {len(batch)} hosts")

    for host in batch:
        # Set host to build mode
        foreman.set_build(host.id)

        # Power cycle via IPMI
        ipmi_power_cycle(host.ipmi_ip)

        # Small delay between individual hosts
        time.sleep(5)

    print(f"Waiting {BATCH_DELAY}s before next batch...")
    time.sleep(BATCH_DELAY)
```

**Foreman Orchestration Queue:**

```ruby
# config/settings.yaml

:orchestration:
  :max_concurrent_builds: 50
  :build_timeout: 3600  # 1 hour
  :build_queue_enabled: true
```

### DHCP Pool Management

**Monitor DHCP usage:**

```bash
#!/bin/bash
# /usr/local/bin/dhcp-pool-monitor

THRESHOLD=80  # Alert if >80% used

TOTAL=$(grep "^dhcp-range" /etc/dnsmasq.d/foreman-proxy.conf | awk -F',' '{print $2}' | awk -F'.' '{print $4}')
LEASES=$(wc -l < /var/lib/misc/dnsmasq.leases)

USAGE=$((LEASES * 100 / TOTAL))

if [ $USAGE -gt $THRESHOLD ]; then
    echo "WARNING: DHCP pool ${USAGE}% full" | \
      logger -t dhcp-monitor
    # Send alert to monitoring
fi
```

### HTTP Connection Limits

**Nginx Rate Limiting:**

```nginx
# Limit concurrent connections per IP
limit_conn_zone $binary_remote_addr zone=addr:10m;
limit_conn addr 10;

# Limit request rate
limit_req_zone $binary_remote_addr zone=one:10m rate=30r/m;
limit_req zone=one burst=50 nodelay;

# Apply to boot file downloads
location /debian/ {
    limit_conn addr 5;
    limit_req zone=one burst=20;
    # ... rest of config
}
```

---

## High Availability Design

### Smart Proxy Redundancy

**Primary/Secondary Smart Proxies per Rack Segment:**

```
Rack 3-5:
  Primary: foreman-proxy-r3-5a (10.10.0.11)
  Secondary: foreman-proxy-r3-5b (10.10.0.14)

Rack 6-9:
  Primary: foreman-proxy-r6-9a (10.10.0.12)
  Secondary: foreman-proxy-r6-9b (10.10.0.15)
```

**Failover Mechanism:**

1. **DHCP Failover**: Configured via ISC DHCP (shown earlier)
2. **TFTP Active/Standby**:
   - Both run TFTP
   - DHCP `next-server` points to primary
   - Manual failover by updating DHCP config
3. **HTTP Load Balanced**:
   ```
   # HAProxy on each Smart Proxy
   listen http-boot
       bind *:80
       balance roundrobin
       server proxy-a 10.10.0.11:8080 check
       server proxy-b 10.10.0.14:8080 check backup
   ```

### Foreman Control Plane HA

**Components:**

1. **PostgreSQL**: 3-node Patroni cluster (leader election)
2. **Foreman App**: 2+ instances behind HAProxy
3. **Redis** (for Foreman caching): Sentinel for HA

**HAProxy Configuration:**
```
# /etc/haproxy/haproxy.cfg

frontend foreman-https
    bind *:443 ssl crt /etc/ssl/foreman.pem
    default_backend foreman-app

backend foreman-app
    balance leastconn
    option httpchk GET /api/status
    server foreman1 10.10.0.8:443 check ssl verify none
    server foreman2 10.10.0.9:443 check ssl verify none

frontend postgresql
    bind *:5432
    default_backend postgres-cluster

backend postgres-cluster
    option pgsql-check user foreman
    server pg1 10.10.0.5:5432 check
    server pg2 10.10.0.6:5432 check backup
    server pg3 10.10.0.7:5432 check backup
```

---

## Monitoring and Debugging

### PXE Boot Monitoring

**Prometheus Metrics:**

```python
# /usr/local/bin/pxe-exporter.py

from prometheus_client import start_http_server, Gauge
import time
import subprocess

pxe_boot_requests = Gauge('pxe_boot_requests_total', 'Total PXE boot requests', ['server'])
tftp_downloads = Gauge('tftp_downloads_active', 'Active TFTP downloads', ['server'])
dhcp_leases = Gauge('dhcp_leases_active', 'Active DHCP leases', ['server'])

def collect_metrics():
    server = 'foreman-proxy-r3-5'

    # Parse DHCP leases
    leases = len(open('/var/lib/misc/dnsmasq.leases').readlines())
    dhcp_leases.labels(server=server).set(leases)

    # Parse TFTP logs
    tftp_active = subprocess.check_output("netstat -an | grep ':69.*ESTABLISHED' | wc -l", shell=True)
    tftp_downloads.labels(server=server).set(int(tftp_active))

if __name__ == '__main__':
    start_http_server(9100)
    while True:
        collect_metrics()
        time.sleep(15)
```

### Serial-Over-LAN Logging

**Capture Installation Progress:**

```bash
#!/bin/bash
# /usr/local/bin/sol-capture.sh <IPMI_HOST> <OUTPUT_FILE>

IPMI_HOST=$1
OUTPUT=$2

ipmitool -I lanplus -H $IPMI_HOST -U admin -P password \
  sol activate | tee $OUTPUT

# Webhook on completion
if grep -q "Installation complete" $OUTPUT; then
    curl -X POST https://foreman.example.com/api/hosts/$HOSTNAME/status \
      -d '{"status": "provisioned"}'
fi
```

### Troubleshooting Dashboard

**Grafana Panels:**

1. **PXE Boot Timeline**: Visualize boot requests over time
2. **Provisioning Funnel**: NEW  DISCOVERING  PROVISIONED (conversion rates)
3. **DHCP Pool Usage**: Real-time lease utilization
4. **TFTP Bandwidth**: Network throughput
5. **HTTP Cache Hit Rate**: Nginx cache efficiency
6. **Failed Provisions**: Hosts stuck in PROVISIONING state

---

## Security Considerations

### Network Isolation

```
┌─────────────────────────────────────┐
│  Provisioning VLAN (50)             │
│  - Isolated from production         │
│  - Firewall rules:                  │
│    • Allow DHCP (67/68)             │
│    • Allow TFTP (69)                │
│    • Allow HTTP (80)                │
│    • Allow DNS (53)                 │
│    • Deny all other inbound         │
│    • Allow outbound to mirrors      │
└─────────────────────────────────────┘
```

### DHCP Security

**Prevent Rogue DHCP:**
- DHCP snooping on switches
- Port security (trusted ports only)
- MAC address filtering

**Prevent Unauthorized Boots:**
```ini
# dnsmasq.conf
dhcp-ignore=tag:!known

# Only serve known MAC addresses (managed by Foreman)
dhcp-hostsfile=/var/lib/foreman-proxy/dhcp/known_macs
```

### Preseed URL Token Authentication

**Foreman Preseed URLs include one-time tokens:**

```
http://foreman.example.com/unattended/preseed?token=abc123def456
```

- Token valid for single use
- Expires after 24 hours
- Logged with host MAC for audit

---

## Performance Benchmarks

### Target Metrics

| Metric | Target | Notes |
|--------|--------|-------|
| **PXE Boot Time** | <30s | DHCP offer to kernel load |
| **Kernel+Initrd Download** | <60s | Via HTTP (300 MB) |
| **Total Install Time** | 12-15min | PXE to OS first boot |
| **Concurrent Provisions** | 100+ | Without degradation |
| **DHCP Response Time** | <100ms | Under full load |
| **TFTP Throughput** | 10 MB/s | Per server |
| **HTTP Throughput** | 1 Gbps | Per Smart Proxy |

### Load Testing

```bash
# Simulate 100 simultaneous PXE boots
for i in {1..100}; do
  (
    MAC=$(printf "52:54:00:%02x:%02x:%02x" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
    echo "Starting VM with MAC $MAC"
    virt-install --pxe --mac=$MAC --memory 2048 --vcpus 2 --disk size=20 --noautoconsole
  ) &
done

wait
echo "All VMs started, monitoring provisioning..."
```

---

## Summary

This network boot infrastructure provides:

1. **High Availability**: No single point of failure
2. **Scalability**: 100+ concurrent provisions
3. **Performance**: HTTP boot, local caching
4. **Security**: Network isolation, token auth
5. **Resilience**: Distributed Smart Proxies
6. **Observability**: Comprehensive monitoring

**Next**: Debian OS image strategy and golden image pipeline.
