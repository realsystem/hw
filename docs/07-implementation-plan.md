# Implementation Plan and Operational Playbooks

## Phase-Based Deployment Strategy

### Timeline Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                     12-Week Implementation Plan                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Week 1-2:   Foundation Infrastructure                              │
│              - Control plane servers                                │
│              - Network configuration                                │
│              - Base monitoring setup                                │
│                                                                      │
│  Week 3-4:   Foreman Deployment                                     │
│              - PostgreSQL Patroni cluster                           │
│              - Foreman HA setup                                     │
│              - Smart Proxy deployment                               │
│                                                                      │
│  Week 5-6:   PXE/Boot Infrastructure                                │
│              - DHCP/TFTP configuration                              │
│              - HTTP boot optimization                               │
│              - Network boot testing                                 │
│                                                                      │
│  Week 7-8:   OS Image Pipeline                                      │
│              - Golden image build                                   │
│              - Debian mirror setup                                  │
│              - Preseed template development                         │
│                                                                      │
│  Week 9-10:  Automation & Integration                               │
│              - IPMI automation scripts                              │
│              - Ansible playbooks (Ceph-ready)                       │
│              - Validation framework                                 │
│                                                                      │
│  Week 11:    Pilot Deployment                                       │
│              - 10-node test cluster                                 │
│              - End-to-end validation                                │
│              - Performance benchmarking                             │
│                                                                      │
│  Week 12:    Production Rollout Planning                            │
│              - Runbook finalization                                 │
│              - Team training                                        │
│              - Go/no-go decision                                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Foundation (Week 1-2)

### Hardware Requirements

**Control Plane Servers:**

| Server | Role | Specs | Quantity |
|--------|------|-------|----------|
| Foreman App | Application server | 16 CPU, 64GB RAM, 500GB SSD | 2 |
| PostgreSQL | Database cluster | 16 CPU, 128GB RAM, 1TB SSD | 3 |
| Smart Proxy | PXE/DHCP/TFTP | 8 CPU, 32GB RAM, 200GB SSD | 3-6 |
| Monitoring | Prometheus/Grafana | 16 CPU, 64GB RAM, 2TB SSD | 2 |
| Image Builder | Packer/CI | 8 CPU, 32GB RAM, 500GB SSD | 1 |

### Network Setup

**VLANs Configuration:**

```bash
# Switch configuration (example for Cisco)

# VLAN 10: Management
vlan 10
 name management
 exit

# VLAN 20: IPMI
vlan 20
 name ipmi
 exit

# VLAN 50: Provisioning
vlan 50
 name provisioning
 exit

# Trunk ports to servers
interface range GigabitEthernet1/0/1-48
 switchport mode trunk
 switchport trunk allowed vlan 10,20,50
 spanning-tree portfast trunk
 exit
```

**Firewall Rules:**

```bash
# iptables rules for provisioning network access
# /etc/iptables/rules.v4 (on gateway)

*filter
:INPUT DROP
:FORWARD DROP
:OUTPUT ACCEPT

# Allow provisioning network outbound (package downloads)
-A FORWARD -s 10.50.0.0/16 -d 0.0.0.0/0 -p tcp --dport 80 -j ACCEPT
-A FORWARD -s 10.50.0.0/16 -d 0.0.0.0/0 -p tcp --dport 443 -j ACCEPT

# Allow control plane to provisioning network
-A FORWARD -s 10.10.0.0/16 -d 10.50.0.0/16 -j ACCEPT
-A FORWARD -s 10.50.0.0/16 -d 10.10.0.0/16 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Deny provisioning to production
-A FORWARD -s 10.50.0.0/16 -d 10.20.0.0/16 -j REJECT
-A FORWARD -s 10.50.0.0/16 -d 10.30.0.0/16 -j REJECT

COMMIT
```

### Day 1-3: Base Server Installation

**1. Install Debian 12 on control plane servers:**

```bash
# Use manual installation or pre-seed
# Configure static IPs, hostname, SSH keys

# Foreman server 1
IP: 10.10.0.8
Hostname: foreman1.example.com

# Foreman server 2
IP: 10.10.0.9
Hostname: foreman2.example.com

# PostgreSQL nodes
IPs: 10.10.0.5-7
Hostnames: pg-patroni-{1,2,3}.example.com
```

**2. Base configuration:**

```bash
# On all servers
apt-get update && apt-get upgrade -y
apt-get install -y vim git curl wget htop net-tools

# Configure NTP
apt-get install -y chrony
systemctl enable --now chrony

# SSH hardening
cat >> /etc/ssh/sshd_config <<EOF
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
EOF
systemctl restart sshd

# Firewall
apt-get install -y iptables-persistent
```

### Day 4-5: PostgreSQL Cluster

**Install Patroni:**

```bash
# On all 3 PostgreSQL nodes
apt-get install -y postgresql-13 python3-pip python3-psycopg2
pip3 install patroni[etcd] python-etcd

# Install etcd on separate nodes or co-locate
apt-get install -y etcd
```

**Configure etcd cluster:**

```yaml
# /etc/etcd/etcd.conf.yml (on etcd nodes)
name: etcd1
data-dir: /var/lib/etcd
initial-cluster-state: new
initial-cluster-token: foreman-cluster
initial-cluster: etcd1=http://10.10.0.2:2380,etcd2=http://10.10.0.3:2380,etcd3=http://10.10.0.4:2380
advertise-client-urls: http://10.10.0.2:2379
listen-client-urls: http://0.0.0.0:2379
initial-advertise-peer-urls: http://10.10.0.2:2380
listen-peer-urls: http://0.0.0.0:2380
```

**Initialize Patroni:**

```bash
# On pg-patroni-1 (bootstrap)
sudo -u postgres patroni /etc/patroni/config.yml

# Verify cluster
patronictl -c /etc/patroni/config.yml list

# Expected output:
# + Cluster: foreman-db (7012345678901234567) ---+---------+
# | Member   | Host       | Role    | State   | TL | Lag in MB |
# +----------+------------+---------+---------+----+-----------+
# | pg-node1 | 10.10.0.5  | Leader  | running |  1 |           |
# | pg-node2 | 10.10.0.6  | Replica | running |  1 |         0 |
# | pg-node3 | 10.10.0.7  | Replica | running |  1 |         0 |
# +----------+------------+---------+---------+----+-----------+
```

**Deploy HAProxy:**

```bash
apt-get install -y haproxy

cat > /etc/haproxy/haproxy.cfg <<'EOF'
global
    maxconn 4096
    log /dev/log local0

defaults
    log global
    mode tcp
    timeout connect 10s
    timeout client 30s
    timeout server 30s

listen postgres
    bind *:5432
    option tcp-check
    tcp-check connect
    server pg1 10.10.0.5:5432 check port 8008 httpchk GET /primary
    server pg2 10.10.0.6:5432 check port 8008 httpchk GET /primary backup
    server pg3 10.10.0.7:5432 check port 8008 httpchk GET /primary backup

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /
    stats refresh 10s
EOF

systemctl restart haproxy
```

**Create Foreman database:**

```bash
sudo -u postgres psql -h 10.10.0.10 -c "CREATE DATABASE foreman_production;"
sudo -u postgres psql -h 10.10.0.10 -c "CREATE USER foreman WITH ENCRYPTED PASSWORD 'secure_password';"
sudo -u postgres psql -h 10.10.0.10 -c "GRANT ALL PRIVILEGES ON DATABASE foreman_production TO foreman;"
```

### Day 6-7: Monitoring Stack

**Deploy Prometheus:**

```bash
# On monitoring server
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar -xzf prometheus-2.45.0.linux-amd64.tar.gz
mv prometheus-2.45.0.linux-amd64 /opt/prometheus

# Systemd service
cat > /etc/systemd/system/prometheus.service <<'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
ExecStart=/opt/prometheus/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=30d
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now prometheus
```

**Deploy Grafana:**

```bash
apt-get install -y software-properties-common
add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
apt-get update
apt-get install -y grafana

systemctl enable --now grafana-server
```

---

## Phase 2: Foreman Deployment (Week 3-4)

### Day 8-10: Foreman Installation

**Install Foreman on both servers:**

```bash
# On foreman1 and foreman2
wget https://yum.theforeman.org/releases/3.7/deb/bookworm/pool/main/f/foreman-release/foreman-release_3.7.0_all.deb
dpkg -i foreman-release_3.7.0_all.deb
apt-get update

# Install Foreman
apt-get install -y foreman foreman-postgresql foreman-cli

# Configure database connection
cat > /etc/foreman/database.yml <<EOF
production:
  adapter: postgresql
  host: 10.10.0.10  # HAProxy VIP
  port: 5432
  database: foreman_production
  username: foreman
  password: secure_password
  pool: 25
  encoding: utf8
EOF

# Initialize database (only on foreman1)
foreman-rake db:migrate
foreman-rake db:seed

# Start Foreman
systemctl enable --now foreman
```

**Configure Apache reverse proxy:**

```bash
# /etc/apache2/sites-available/foreman-ssl.conf
<VirtualHost *:443>
    ServerName foreman.example.com
    ServerAlias foreman1.example.com foreman2.example.com

    SSLEngine on
    SSLCertificateFile /etc/foreman/certs/foreman.crt
    SSLCertificateKeyFile /etc/foreman/certs/foreman.key
    SSLCACertificateFile /etc/foreman/certs/ca.crt

    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/
    ProxyPreserveHost On
</VirtualHost>

a2ensite foreman-ssl
a2enmod ssl proxy proxy_http
systemctl restart apache2
```

### Day 11-12: Smart Proxy Deployment

**Install Smart Proxy:**

```bash
# On each Smart Proxy server (3-6 nodes)
apt-get install -y foreman-proxy

cat > /etc/foreman-proxy/settings.yml <<EOF
---
:settings_directory: /etc/foreman-proxy/settings.d
:trusted_hosts:
  - foreman.example.com
  - foreman1.example.com
  - foreman2.example.com
:foreman_url: https://foreman.example.com
:bind_host: '*'
:https_port: 8443
:log_file: /var/log/foreman-proxy/proxy.log
:log_level: INFO
EOF
```

**Enable DHCP module:**

```bash
cat > /etc/foreman-proxy/settings.d/dhcp.yml <<EOF
---
:enabled: true
:use_provider: dhcp_isc
:server: 127.0.0.1
:subnets: [10.50.3.0/22, 10.50.6.0/22]
:omapi_port: 7911
EOF

# Install ISC DHCP
apt-get install -y isc-dhcp-server

# Configure dhcpd
cat > /etc/dhcp/dhcpd.conf <<'EOF'
omapi-port 7911;
omapi-key omapi_key;

subnet 10.50.3.0 netmask 255.255.252.0 {
  range 10.50.3.100 10.50.5.254;
  option routers 10.50.0.1;
  option domain-name-servers 10.5.0.1, 10.5.0.2;
  next-server 10.10.0.11;
  filename "pxelinux.0";
}

include "/var/lib/foreman-proxy/dhcp/dhcpd.hosts";
EOF

systemctl restart isc-dhcp-server
```

**Enable TFTP module:**

```bash
cat > /etc/foreman-proxy/settings.d/tftp.yml <<EOF
---
:enabled: true
:tftp_root: /var/lib/tftpboot
:tftp_servername: 10.10.0.11
EOF

apt-get install -y tftpd-hpa
systemctl enable --now tftpd-hpa
```

**Register Smart Proxy with Foreman:**

```bash
hammer proxy create \
  --name "foreman-proxy-r3-5" \
  --url "https://foreman-proxy-r3-5.example.com:8443"
```

### Day 13-14: Hostgroup and Template Configuration

**Create Hostgroups:**

```bash
# Ceph OSD nodes
hammer hostgroup create \
  --name "ceph-osd-nodes" \
  --architecture "x86_64" \
  --operatingsystem "Debian 12" \
  --medium "Debian mirror" \
  --partition-table "Ceph OSD Preseed" \
  --subnet "provisioning" \
  --domain "example.com"

# Ceph MON nodes
hammer hostgroup create \
  --name "ceph-mon-nodes" \
  --architecture "x86_64" \
  --operatingsystem "Debian 12" \
  --medium "Debian mirror" \
  --partition-table "Ceph MON Preseed" \
  --subnet "provisioning" \
  --domain "example.com"
```

**Upload Preseed templates** (created in previous docs)

---

## Phase 3: PXE Infrastructure (Week 5-6)

### TFTP Directory Structure Setup

```bash
mkdir -p /var/lib/tftpboot/{boot,pxelinux.cfg,grub2}

# Download PXE bootloaders
cd /var/lib/tftpboot
wget http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/pxelinux.0
wget http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux -O boot/debian-12-amd64-linux
wget http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz -O boot/debian-12-amd64-initrd.gz

# Set permissions
chown -R tftp:tftp /var/lib/tftpboot
chmod -R 755 /var/lib/tftpboot
```

### HTTP Boot Server

```bash
apt-get install -y nginx

cat > /etc/nginx/sites-available/pxe-boot <<'EOF'
server {
    listen 80;
    server_name foreman-proxy-r3-5.example.com;

    location /debian/ {
        alias /var/www/debian/;
        autoindex on;
    }

    location /unattended/ {
        proxy_pass https://foreman.example.com;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

ln -s /etc/nginx/sites-available/pxe-boot /etc/nginx/sites-enabled/
systemctl restart nginx
```

---

## Phase 4: OS Image Pipeline (Week 7-8)

### Build Golden Image

```bash
# On image builder server
apt-get install -y packer qemu-kvm libvirt-daemon-system

# Clone provisioning repo
git clone https://github.com/yourorg/ceph-provisioning.git
cd ceph-provisioning/packer

# Build Debian 12 golden image
packer build debian-12-ceph.pkr.hcl

# Output artifacts:
# - output-debian-12-ceph/debian-12-ceph.qcow2
# - artifacts/pxe/vmlinuz-6.1.0-18-amd64
# - artifacts/pxe/initrd.img-6.1.0-18-amd64
```

### Deploy to Smart Proxies

```bash
# Sync to all Smart Proxies
for proxy in proxy-r3-5 proxy-r6-9 proxy-r10-12; do
    rsync -avz artifacts/pxe/ $proxy:/var/lib/tftpboot/boot/
done
```

---

## Phase 5: Automation (Week 9-10)

### IPMI Automation Scripts

Deploy all scripts from [docs/04-hardware-automation.md](04-hardware-automation.md:1):
```bash
rsync -avz scripts/ipmi/ foreman-proxy-r3-5:/usr/local/bin/
```

### Ansible Playbooks

```bash
# Deploy Ceph-ready playbooks
cd ansible
ansible-galaxy install -r requirements.yml
ansible-playbook -i inventory/foreman.py playbooks/ceph_baseline.yml --check
```

---

## Phase 6: Pilot Deployment (Week 11)

### 10-Node Test Cluster

```bash
# Identify 10 test nodes (rack 7, units 12-21)
TEST_NODES="ceph-osd-r07-u{12..21}"

# Step 1: IPMI discovery
for unit in {12..21}; do
    ipmi-exec.sh 10.20.7.$unit mc info
done

# Step 2: Register in Foreman
for unit in {12..21}; do
    hammer host create \
        --name "ceph-osd-r07-u$unit" \
        --hostgroup "ceph-osd-nodes" \
        --compute-resource "ipmi-rack7" \
        --compute-attributes "ipmi_address=10.20.7.$unit"
done

# Step 3: Trigger discovery
for unit in {12..21}; do
    ipmi-bootdev.sh 10.20.7.$unit pxe
    ipmi-power.sh 10.20.7.$unit cycle
done

# Monitor discovery progress
watch "hammer host list --search 'hostgroup=ceph-osd-nodes AND lifecycle_state=DISCOVERING'"

# Step 4: Approve and provision
hammer host bulk-action --search "lifecycle_state=DISCOVERED" --action build

# Step 5: Monitor provisioning
watch "hammer host list --search 'build_status=true' --fields name,lifecycle_state"

# Step 6: Validate
for unit in {12..21}; do
    ssh ceph-osd-r07-u$unit '/usr/local/bin/validate-ceph-ready.sh'
done
```

### Benchmarking

```bash
# Provisioning time measurement
START=$(date +%s)
# ... provision nodes ...
END=$(date +%s)
echo "Provisioning time: $((END - START)) seconds"

# Target: 15-20 minutes per node
```

---

## Operational Playbooks

### Playbook 1: Provision New Node

```bash
#!/bin/bash
# provision-node.sh <ipmi_address> <hostname>

IPMI_ADDR=$1
HOSTNAME=$2

echo "=== Provisioning $HOSTNAME ==="

# 1. Hardware pre-check
/usr/local/bin/hardware-precheck.sh $IPMI_ADDR
if [ $? -ne 0 ]; then
    echo "ERROR: Hardware pre-check failed"
    exit 1
fi

# 2. Register in Foreman
hammer host create \
    --name "$HOSTNAME" \
    --hostgroup "ceph-osd-nodes" \
    --compute-resource "ipmi-pool" \
    --compute-attributes "ipmi_address=$IPMI_ADDR" \
    --build true

# 3. Trigger PXE boot
ipmi-bootdev.sh $IPMI_ADDR pxe persistent
ipmi-power.sh $IPMI_ADDR cycle

# 4. Monitor progress
echo "Waiting for installation to complete..."
while true; do
    STATE=$(hammer host info --name "$HOSTNAME" --fields "Lifecycle state" | grep "Lifecycle state" | awk '{print $3}')
    echo "Current state: $STATE"

    if [ "$STATE" == "READY_CEPH" ]; then
        echo " Provisioning complete!"
        break
    elif [[ "$STATE" == *"FAILED"* ]]; then
        echo " Provisioning failed!"
        exit 1
    fi

    sleep 60
done

# 5. Final validation
ssh $HOSTNAME '/usr/local/bin/validate-ceph-ready.sh'
```

### Playbook 2: Decommission Node

```bash
#!/bin/bash
# decommission-node.sh <hostname>

HOSTNAME=$1

echo "=== Decommissioning $HOSTNAME ==="

# 1. Remove from Ceph (handled by ceph-ansible)
# ... ceph osd out / ceph osd purge ...

# 2. Update Foreman state
hammer host update --name "$HOSTNAME" \
    --parameter "lifecycle_state=DECOMMISSIONED"

# 3. Power off
IPMI_ADDR=$(hammer host info --name "$HOSTNAME" --fields "IPMI Address" | awk '{print $3}')
ipmi-power.sh $IPMI_ADDR soft

echo "Node decommissioned and powered off"
```

### Playbook 3: Firmware Update

```bash
#!/bin/bash
# firmware-update-rack.sh <rack_number>

RACK=$1

echo "=== Firmware Update for Rack $RACK ==="

# 1. Get nodes in rack
NODES=$(hammer host list --search "rack=r$RACK" --fields name | tail -n +2)

# 2. For each node
for node in $NODES; do
    echo "Updating $node..."

    # Decommission from Ceph
    # ... ceph osd out $node ...

    # Get IPMI address
    IPMI=$(hammer host info --name "$node" --fields "IPMI Address" | awk '{print $3}')

    # Update firmware
    /usr/local/bin/firmware-update.sh $IPMI bios

    # Validate
    sleep 300  # Wait for reboot
    /usr/local/bin/hardware-precheck.sh $IPMI

    # Re-provision if needed
    # ... or add back to Ceph ...

    echo "$node complete"
    sleep 600  # 10 min between nodes
done
```

---

## Success Criteria

### Pre-Production Checklist

- [ ] All control plane services HA validated (PostgreSQL, Foreman, Smart Proxies)
- [ ] 10-node pilot cluster successfully provisioned
- [ ] Average provision time < 20 minutes
- [ ] Zero provisioning failures in pilot (or < 1%)
- [ ] All nodes pass validation tests
- [ ] Monitoring dashboards operational
- [ ] Alert notifications tested (PagerDuty, Slack)
- [ ] Disaster recovery tested (database restore, config restore)
- [ ] Team trained on operational playbooks
- [ ] Documentation complete and reviewed

### Performance Targets

| Metric | Target | Measured |
|--------|--------|----------|
| Provision time (PXE to READY_CEPH) | 15-20 min | ___ min |
| Concurrent provisions | 100+ | ___ |
| DHCP response time | < 100ms | ___ ms |
| Failure rate | < 1% | ___% |
| Time to recovery (failed provision) | < 30 min | ___ min |

---

## Production Rollout

### Phased Deployment

**Phase 1: Rack 7 (33 nodes)**
- 1 week
- Closely monitored
- Daily standups

**Phase 2: Racks 8-9 (66 nodes)**
- 2 weeks
- Automated batches of 20

**Phase 3: Racks 10-15 (200 nodes)**
- 4 weeks
- Automated batches of 50

**Phase 4: Remaining racks (700+ nodes)**
- 8 weeks
- Full automation, minimal intervention

### Go/No-Go Criteria

**GO if:**
- Pilot success rate > 99%
- All critical alerts firing correctly
- Team confidence level high
- No outstanding critical bugs

**NO-GO if:**
- Failure rate > 2%
- Unresolved blocking issues
- Team not adequately trained
- Monitoring gaps identified

---

## Summary

This implementation plan provides:

1. **12-week timeline** from foundation to production readiness
2. **Phased approach** reducing risk
3. **Detailed technical steps** for each component
4. **Operational playbooks** for common tasks
5. **Success criteria** for go/no-go decisions
6. **Production rollout strategy** scaling to 1000+ nodes

**The platform is now ready for enterprise-scale Ceph cluster deployment.**
