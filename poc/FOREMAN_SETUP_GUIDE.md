# Foreman Control Plane Setup Guide

## Prerequisites for This Guide

**Before deploying Foreman, you need:**

### Infrastructure
- [ ] 1-2 servers for Foreman (16 CPU, 64GB RAM, 500GB disk each)
- [ ] 1-3 servers for PostgreSQL (16 CPU, 128GB RAM, 1TB disk each)
- [ ] 1-3 servers for Smart Proxy (8 CPU, 32GB RAM, 200GB disk each)
- [ ] Network access to target bare-metal servers
- [ ] VLAN for provisioning (e.g., VLAN 50, 10.50.0.0/16)

### Operating System
- Debian 12 (Bookworm) - recommended
- Ubuntu 22.04 LTS - also supported
- RHEL 8/9 or Rocky Linux - for Red Hat ecosystem

### Network Requirements
- Static IP addresses for all control plane servers
- DNS entries (optional but recommended)
- Firewall rules configured (see below)

---

## Deployment Options

### Quick Start: All-in-One Foreman (POC/Testing)

**For POC only** - Single server with everything:

```bash
# On a Debian 12 server (16 CPU, 64GB RAM minimum)

# 1. Install Foreman with installer (includes PostgreSQL, Smart Proxy)
wget https://apt.theforeman.org/foreman.asc -O /etc/apt/trusted.gpg.d/foreman.asc
echo "deb http://deb.theforeman.org/ bookworm 3.7" > /etc/apt/sources.list.d/foreman.list
apt-get update
apt-get install -y foreman-installer

# 2. Run installer (this takes 15-30 minutes)
foreman-installer \
  --foreman-initial-admin-username admin \
  --foreman-initial-admin-password changeme \
  --enable-foreman-proxy \
  --foreman-proxy-tftp true \
  --foreman-proxy-dhcp true \
  --foreman-proxy-dhcp-interface eth0 \
  --foreman-proxy-dhcp-range "10.50.3.100 10.50.15.254" \
  --foreman-proxy-dhcp-gateway 10.50.0.1 \
  --foreman-proxy-dhcp-nameservers "10.5.0.1,10.5.0.2"

# 3. Access Foreman
# Open browser: https://<server-ip>
# Login: admin / changeme
```

**Timeline:** 1-2 hours
**Use case:** POC, testing, learning
**NOT for production** (no HA)

---

### Production Deployment: High Availability

**For production** - Distributed, HA setup:

#### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Production Foreman Architecture                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Load Balancer (HAProxy + Keepalived)                       │
│  VIP: 10.10.0.10                                            │
│         │                                                    │
│         ├──────────┬──────────┐                            │
│         ▼          ▼          ▼                             │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐                      │
│  │Foreman 1│ │Foreman 2│ │Foreman 3│                      │
│  │10.10.0.8│ │10.10.0.9│ │10.10.0.11│                     │
│  └────┬────┘ └────┬────┘ └────┬────┘                      │
│       │           │           │                             │
│       └───────────┴───────────┘                            │
│                   │                                         │
│                   ▼                                         │
│  ┌──────────────────────────────────────┐                  │
│  │ PostgreSQL Patroni Cluster           │                  │
│  │ ┌──────────┐ ┌──────────┐ ┌────────┐│                  │
│  │ │Primary   │ │Standby 1 │ │Standby│││                  │
│  │ │10.10.0.5 │ │10.10.0.6 │ │10.10.07││                  │
│  │ └──────────┘ └──────────┘ └────────┘│                  │
│  │ VIP: 10.10.0.4 (via HAProxy)        │                  │
│  └──────────────────────────────────────┘                  │
│                                                              │
│  Smart Proxies (Distributed)                                │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐          │
│  │Proxy Rack 3 │ │Proxy Rack 6 │ │Proxy Rack 10│          │
│  │10.10.0.11   │ │10.10.0.12   │ │10.10.0.13   │          │
│  └─────────────┘ └─────────────┘ └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

**Timeline:** 1-2 weeks
**Use case:** Production (1000+ nodes)

---

## Step-by-Step: All-in-One Installation (Quickest)

This gets you up and running in **1-2 hours** for POC purposes.

### Step 1: Prepare Server

```bash
# SSH to your Foreman server
ssh root@foreman-server

# Update system
apt-get update && apt-get upgrade -y

# Install prerequisites
apt-get install -y \
  ca-certificates \
  gnupg \
  lsb-release \
  wget \
  vim \
  net-tools

# Set hostname
hostnamectl set-hostname foreman.example.com

# Configure /etc/hosts
cat >> /etc/hosts <<EOF
10.10.0.8  foreman.example.com foreman
EOF
```

### Step 2: Install Foreman Repository

```bash
# Add Foreman GPG key
wget https://apt.theforeman.org/foreman.asc -O /etc/apt/trusted.gpg.d/foreman.asc

# Add Foreman repository (3.7 is latest stable)
echo "deb http://deb.theforeman.org/ bookworm 3.7" > /etc/apt/sources.list.d/foreman.list

# Add Puppet repository (required by Foreman)
echo "deb http://apt.puppet.com bookworm puppet7" > /etc/apt/sources.list.d/puppet.list
wget https://apt.puppet.com/keyring.gpg -O /etc/apt/trusted.gpg.d/puppet.gpg

# Update package lists
apt-get update
```

### Step 3: Install Foreman Installer

```bash
apt-get install -y foreman-installer
```

### Step 4: Run Installer

**Basic installation (minimal):**
```bash
foreman-installer \
  --foreman-initial-admin-username admin \
  --foreman-initial-admin-password changeme123
```

**Or with Smart Proxy enabled (recommended):**
```bash
foreman-installer \
  --foreman-initial-admin-username admin \
  --foreman-initial-admin-password changeme123 \
  --enable-foreman-proxy \
  --foreman-proxy-tftp true \
  --foreman-proxy-tftp-servername 10.10.0.8 \
  --foreman-proxy-dhcp true \
  --foreman-proxy-dhcp-interface eth0 \
  --foreman-proxy-dhcp-range "10.50.3.100 10.50.15.254" \
  --foreman-proxy-dhcp-gateway 10.50.0.1 \
  --foreman-proxy-dhcp-nameservers "10.5.0.1,10.5.0.2" \
  --foreman-proxy-dns false \
  --foreman-proxy-bmc false
```

**Installation takes 15-30 minutes.** You'll see:
```
  Success!
  * Foreman is running at https://foreman.example.com
      Initial credentials are admin / changeme123
  * Foreman Proxy is running at https://foreman.example.com:8443
```

### Step 5: Verify Installation

```bash
# Check services
systemctl status foreman
systemctl status foreman-proxy
systemctl status postgresql

# Test web interface
curl -k https://localhost/api/status
# Should return: {"status":"ok","version":"3.7.0"}

# Test authentication
curl -k -u admin:changeme123 https://localhost/api/v2/architectures
# Should return JSON list
```

### Step 6: Access Foreman UI

```bash
# Get server IP
ip addr show eth0 | grep "inet "

# Open in browser:
# https://<server-ip>

# Login:
# Username: admin
# Password: changeme123
```

**You should see the Foreman dashboard!** 

---

## Post-Installation Configuration

### Step 7: Configure Debian Repository

**Option 1: Use Debian.org (internet access required)**

```bash
# In Foreman UI:
# 1. Navigate to Hosts  Installation Media
# 2. Create New Medium
#    - Name: Debian mirror
#    - Path: http://deb.debian.org/debian
#    - OS Family: Debian

# Or via hammer CLI:
hammer medium create \
  --name "Debian mirror" \
  --path "http://deb.debian.org/debian" \
  --os-family "Debian"
```

**Option 2: Create Local Mirror (recommended for production)**

```bash
# On Foreman server or separate mirror server
apt-get install -y apache2 debmirror

# Create mirror directory
mkdir -p /var/www/html/debian

# Mirror Debian 12
debmirror \
  --method=http \
  --host=deb.debian.org \
  --root=/debian \
  --dist=bookworm,bookworm-updates,bookworm-security \
  --section=main,contrib,non-free-firmware \
  --arch=amd64 \
  --passive \
  --progress \
  /var/www/html/debian

# Point Foreman to local mirror
hammer medium create \
  --name "Debian mirror" \
  --path "http://10.10.0.8/debian" \
  --os-family "Debian"
```

### Step 8: Import Debian Operating System

```bash
# This creates OS entry in Foreman
hammer os create \
  --name "Debian" \
  --major "12" \
  --minor "5" \
  --family "Debian" \
  --architecture-ids 1 \
  --medium-ids 1

# Associate with partition tables
hammer os update \
  --id 1 \
  --partition-table-ids 1,2
```

### Step 9: Configure Subnets

```bash
# Provisioning subnet
hammer subnet create \
  --name "Provisioning" \
  --network "10.50.0.0" \
  --mask "255.255.0.0" \
  --gateway "10.50.0.1" \
  --dns-primary "10.5.0.1" \
  --dns-secondary "10.5.0.2" \
  --from "10.50.3.100" \
  --to "10.50.15.254" \
  --ipam "DHCP" \
  --boot-mode "DHCP" \
  --dhcp-id 1 \
  --tftp-id 1

# Management subnet
hammer subnet create \
  --name "Management" \
  --network "10.10.0.0" \
  --mask "255.255.0.0" \
  --gateway "10.10.0.1" \
  --dns-primary "10.5.0.1"
```

### Step 10: Test Discovery

```bash
# Power on a test server via IPMI
ipmitool -I lanplus -H 10.20.7.12 -U ADMIN -P ADMIN \
  chassis bootdev pxe options=persistent
ipmitool -I lanplus -H 10.20.7.12 -U ADMIN -P ADMIN \
  chassis power on

# Wait 5-10 minutes, then check:
hammer discovered-host list

# Should show discovered hardware
```

---

## Firewall Configuration

### Required Ports

```bash
# Allow these ports on Foreman server
ufw allow 80/tcp    # HTTP (redirects to HTTPS)
ufw allow 443/tcp   # HTTPS (Web UI, API)
ufw allow 8443/tcp  # Smart Proxy API
ufw allow 67/udp    # DHCP
ufw allow 68/udp    # DHCP
ufw allow 69/udp    # TFTP
ufw allow 8140/tcp  # Puppet (optional)
ufw allow 5432/tcp  # PostgreSQL (from Foreman only)
```

**Or with iptables:**
```bash
cat > /etc/iptables/rules.v4 <<'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Loopback
-A INPUT -i lo -j ACCEPT

# Established connections
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# SSH
-A INPUT -p tcp --dport 22 -j ACCEPT

# Foreman Web UI/API
-A INPUT -p tcp --dport 80 -j ACCEPT
-A INPUT -p tcp --dport 443 -j ACCEPT
-A INPUT -p tcp --dport 8443 -j ACCEPT

# DHCP
-A INPUT -p udp --dport 67:68 -j ACCEPT

# TFTP
-A INPUT -p udp --dport 69 -j ACCEPT

# PostgreSQL (only from localhost or specific IPs)
-A INPUT -p tcp --dport 5432 -s 127.0.0.1 -j ACCEPT

# Reject all other
-A INPUT -j REJECT --reject-with icmp-host-prohibited

COMMIT
EOF

iptables-restore < /etc/iptables/rules.v4
```

---

## Verification Checklist

Before running the Terraform POC, verify:

- [ ] Foreman web UI accessible (https://foreman.example.com)
- [ ] Can login with admin credentials
- [ ] PostgreSQL running: `systemctl status postgresql`
- [ ] Foreman Proxy running: `systemctl status foreman-proxy`
- [ ] DHCP working: `systemctl status isc-dhcp-server` or `dnsmasq`
- [ ] TFTP directory exists: `ls -la /var/lib/tftpboot`
- [ ] Debian repository configured in Foreman
- [ ] Subnets created with DHCP/TFTP associations
- [ ] Smart Proxy shows "green" in Foreman UI (Infrastructure  Smart Proxies)
- [ ] API accessible: `curl -k https://foreman.example.com/api/status`

**All green?** You're ready for the Terraform POC! 

---

## Troubleshooting

### Issue: Installer Fails

```bash
# Check logs
tail -f /var/log/foreman-installer/foreman-installer.log

# Common fixes:
# 1. Ensure hostname is FQDN
hostnamectl set-hostname foreman.example.com

# 2. Ensure /etc/hosts is correct
cat /etc/hosts | grep foreman

# 3. Re-run installer
foreman-installer --reset-data  # WARNING: Clears database!
```

### Issue: Can't Access Web UI

```bash
# Check Apache/Nginx
systemctl status apache2

# Check Foreman service
systemctl status foreman

# Check firewall
iptables -L -n | grep 443

# Check logs
tail -f /var/log/foreman/production.log
```

### Issue: DHCP Not Working

```bash
# Check DHCP service
systemctl status isc-dhcp-server
# or
systemctl status dnsmasq

# Check DHCP config
cat /etc/dhcp/dhcpd.conf

# Test DHCP manually
dhcping -s 10.50.0.1 -h 00:25:90:aa:bb:cc
```

### Issue: TFTP Not Serving Files

```bash
# Check TFTP service
systemctl status tftpd-hpa

# Check files exist
ls -la /var/lib/tftpboot/

# Test TFTP manually
tftp 10.10.0.8
tftp> get pxelinux.0
tftp> quit
ls -la pxelinux.0  # Should exist
```

---

## Quick Start Summary

**Minimum viable Foreman for POC:**

```bash
# 1. Install (on Debian 12 server)
wget https://apt.theforeman.org/foreman.asc -O /etc/apt/trusted.gpg.d/foreman.asc
echo "deb http://deb.theforeman.org/ bookworm 3.7" > /etc/apt/sources.list.d/foreman.list
apt-get update && apt-get install -y foreman-installer

# 2. Run installer
foreman-installer \
  --foreman-initial-admin-username admin \
  --foreman-initial-admin-password changeme123 \
  --enable-foreman-proxy \
  --foreman-proxy-tftp true \
  --foreman-proxy-dhcp true

# 3. Configure (in Web UI)
# - Add Debian repository
# - Create subnets
# - Verify Smart Proxy

# 4. Test
curl -k -u admin:changeme123 https://localhost/api/v2/architectures

# 5. Ready for Terraform POC!
```

**Timeline:** 2-3 hours for first-time setup

---

## Alternative: Use Terraform to Deploy Foreman

I can also create Terraform configs to deploy the Foreman infrastructure itself (using VMware/Proxmox/AWS providers). Would you like that?

---

## Next Steps

Once Foreman is deployed:

1. **Update terraform.tfvars** with your Foreman URL
2. **Test connection**: `cd terraform/00-provider && terraform apply`
3. **Run POC**: Follow [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)

**Foreman deployed?**  Continue to Terraform POC
**Need help?**  Check Foreman documentation: https://theforeman.org/manuals/3.7/

---

**Questions?** This is the most time-consuming part (Foreman setup). Once it's running, the Terraform POC takes only 90 minutes.
