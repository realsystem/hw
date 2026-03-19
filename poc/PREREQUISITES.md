# POC Prerequisites - READ THIS FIRST

## Critical: What You Need BEFORE Starting

This POC is **NOT a complete "from-scratch" deployment**. It assumes you have certain infrastructure **already deployed and running**.

---

## Two Deployment Paths

### Path 1: You Already Have Foreman 

**If you have:**
-  Foreman 3.0+ running and accessible
-  PostgreSQL database configured
-  Smart Proxy with DHCP/TFTP enabled
-  Debian repository configured
-  Admin credentials

**Then:**
```bash
# You can start the POC immediately
cd /path/to/poc
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Add your Foreman URL/credentials
./quick-start.sh
```

**Timeline:** 90 minutes (POC only)

---

### Path 2: You're Starting from Scratch 

**If you DON'T have Foreman deployed yet:**

You must **first deploy** the Foreman control plane before running this POC.

```
Step 1: Deploy Foreman Infrastructure (1-2 hours)
   
Step 2: Verify Foreman is working
   
Step 3: Run this POC (90 minutes)
```

**Follow this order:**
1. Read **[FOREMAN_SETUP_GUIDE.md](FOREMAN_SETUP_GUIDE.md)**  Start here!
2. Deploy Foreman (all-in-one quickstart = 1-2 hours)
3. Verify Foreman is accessible
4. Then run this POC

**Timeline:** 3-4 hours total (2-3h Foreman + 90min POC)

---

## What This POC Does vs. Doesn't Do

###  This POC DOES:

- Configure Foreman resources (hostgroups, subnets)
- Discover bare-metal hardware
- Trigger OS installation on discovered nodes
- Configure nodes with Ansible (network, kernel, storage)
- Validate node configuration
- Generate Ceph inventory

###  This POC Does NOT:

- Install Foreman server
- Install PostgreSQL
- Install Smart Proxy
- Configure DHCP/TFTP from scratch
- Set up network infrastructure (VLANs, switches)
- Deploy Ceph cluster (that's the next step after POC)

---

## Complete Infrastructure Requirements

### Must Exist BEFORE POC:

#### 1. Foreman Control Plane

```
┌─────────────────────────────────────────────┐
│  Foreman Server                             │
│  - Web UI at https://foreman.example.com    │
│  - API accessible                           │
│  - PostgreSQL database                      │
│  - Admin credentials: admin / password      │
└─────────────────────────────────────────────┘
```

**How to get:** See [FOREMAN_SETUP_GUIDE.md](FOREMAN_SETUP_GUIDE.md)

**Options:** All-in-one (1-2 hours) or Production HA (1-2 weeks)

#### 2. Smart Proxy with PXE Boot

```
┌─────────────────────────────────────────────┐
│  Smart Proxy (can be same server as Foreman)│
│  - DHCP server running                      │
│  - TFTP server running                      │
│  - HTTP server for boot files               │
│  - Registered with Foreman                  │
└─────────────────────────────────────────────┘
```

**Included in:** All-in-one Foreman installer (see above)

**Or separate:** Deploy additional Smart Proxies per rack

#### 3. Network Infrastructure

```
┌─────────────────────────────────────────────┐
│  Network Requirements                        │
│  - Provisioning VLAN configured (e.g. 50)   │
│  - Management VLAN configured (e.g. 10)      │
│  - IPMI network accessible (e.g. 20)        │
│  - Switches configured for PXE boot         │
│  - Firewall rules allow DHCP/TFTP/HTTP      │
└─────────────────────────────────────────────┘
```

**Manual setup required** - This POC doesn't configure networks

#### 4. Target Hardware

```
┌─────────────────────────────────────────────┐
│  Bare-Metal Servers (3+ for POC)             │
│  - Supermicro X9 or similar                  │
│  - IPMI enabled and accessible               │
│  - Connected to provisioning network         │
│  - Ready to PXE boot                         │
└─────────────────────────────────────────────┘
```

**Must be racked and cabled** before POC

#### 5. Client Tools (on your workstation)

```bash
# Check you have these installed:
terraform --version  # Need 1.6+
ansible --version    # Need 2.15+
jq --version        # For JSON parsing
ssh-keygen          # For SSH keys
```

---

## Detailed Checklist

### Foreman Infrastructure 

- [ ] Foreman server deployed (physical or VM)
- [ ] Web UI accessible at https://foreman.example.com
- [ ] Can login with admin credentials
- [ ] PostgreSQL running: `systemctl status postgresql`
- [ ] Foreman service running: `systemctl status foreman`

### Smart Proxy 

- [ ] Smart Proxy running: `systemctl status foreman-proxy`
- [ ] DHCP service running: `systemctl status isc-dhcp-server` or `dnsmasq`
- [ ] TFTP service running: `systemctl status tftpd-hpa`
- [ ] Smart Proxy registered with Foreman (check UI: Infrastructure  Smart Proxies)
- [ ] DHCP scope configured for provisioning network

### Debian Repository 

- [ ] Debian mirror configured in Foreman
- [ ] Can access: http://deb.debian.org/debian (or local mirror)
- [ ] Operating System "Debian 12" exists in Foreman
- [ ] Installation media configured

### Network 

- [ ] Provisioning VLAN created (e.g., VLAN 50, 10.50.0.0/16)
- [ ] Management VLAN created (e.g., VLAN 10, 10.10.0.0/16)
- [ ] IPMI network accessible (e.g., 10.20.0.0/16)
- [ ] Switch ports configured for PXE boot
- [ ] Firewall allows:
  - [ ] DHCP (UDP 67/68)
  - [ ] TFTP (UDP 69)
  - [ ] HTTP (TCP 80)
  - [ ] HTTPS (TCP 443) to Foreman

### Hardware 

- [ ] 3+ servers racked and cabled
- [ ] IPMI configured and accessible
- [ ] Power cables connected
- [ ] Network cables connected to provisioning VLAN
- [ ] IPMI credentials known (usually ADMIN/ADMIN default)

### Client Workstation 

- [ ] Terraform 1.6+ installed
- [ ] Ansible 2.15+ installed
- [ ] jq installed
- [ ] SSH keys generated (`ssh-keygen`)
- [ ] Network access to Foreman server
- [ ] Can reach IPMI network (for scripts)

---

## Verification Tests

### Test 1: Foreman API

```bash
# Should return JSON status
curl -k https://foreman.example.com/api/status

# Expected output:
# {"status":"ok","version":"3.7.0"}
```

### Test 2: Authentication

```bash
# Should return JSON (not 401 Unauthorized)
curl -k -u "admin:changeme123" \
  https://foreman.example.com/api/v2/architectures | jq .
```

### Test 3: Smart Proxy

```bash
# Check in Foreman UI
# Navigate to: Infrastructure  Smart Proxies
# Should show green status for:
#   - DHCP
#   - TFTP
#   - Logs

# Or via API:
curl -k -u "admin:changeme123" \
  https://foreman.example.com/api/v2/smart_proxies | jq .
```

### Test 4: DHCP/TFTP

```bash
# From a server on the provisioning network:
# Test DHCP
dhclient -v eth0

# Test TFTP
tftp foreman.example.com
tftp> get pxelinux.0
tftp> quit
ls -la pxelinux.0  # Should exist
```

### Test 5: PXE Boot (End-to-End)

```bash
# Power on a test server
ipmitool -I lanplus -H 10.20.7.12 -U ADMIN -P ADMIN \
  chassis bootdev pxe options=persistent
ipmitool -I lanplus -H 10.20.7.12 -U ADMIN -P ADMIN \
  chassis power on

# Watch serial console (optional)
ipmitool -I lanplus -H 10.20.7.12 -U ADMIN -P ADMIN sol activate

# Should see:
# 1. DHCP request
# 2. TFTP download of pxelinux.0
# 3. Boot menu or discovery image
```

**If this test passes, you're ready for the POC!** 

---

## Common Mistakes

###  Mistake 1: Running POC Without Foreman

**Symptom:**
```
Error: Failed to initialize Foreman provider
Error: Connection refused to foreman.example.com
```

**Fix:** Deploy Foreman first (see [FOREMAN_SETUP_GUIDE.md](FOREMAN_SETUP_GUIDE.md))

###  Mistake 2: Foreman Deployed But Not Configured

**Symptom:**
```
Error: Operating system not found
Error: Subnet not found
```

**Fix:** Complete Foreman post-installation configuration:
- Import Debian OS
- Configure subnets
- Associate Smart Proxy

###  Mistake 3: Network Not Ready

**Symptom:**
- Nodes don't PXE boot
- Discovery fails
- DHCP timeouts

**Fix:** Verify network infrastructure:
- VLANs configured on switches
- DHCP scope matches provisioning network
- Firewall allows PXE traffic

###  Mistake 4: No Hardware Available

**Symptom:**
```
No discovered hosts found
```

**Fix:**
- Power on servers
- Verify IPMI accessible
- Check servers connected to correct VLAN
- Wait 5-10 minutes for discovery

---

## Deployment Timeline

**From scratch**: Week 1 (planning)  Week 2 (Foreman)  Week 3 (POC)  Week 4 (scale testing)

**With Foreman**: Day 1-2 (setup + execution)  Day 3 (analysis)

---

## Getting Help

### If You're Stuck on Foreman Setup:

1. **Read:** [FOREMAN_SETUP_GUIDE.md](FOREMAN_SETUP_GUIDE.md)
2. **Watch:** Foreman Quick Start videos: https://theforeman.org/media.html
3. **Ask:** Foreman Community: https://community.theforeman.org/
4. **Docs:** Official docs: https://theforeman.org/manuals/3.7/

### If You're Stuck on Terraform POC:

1. **Read:** [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
2. **Check:** [README.md](README.md#troubleshooting)
3. **Debug:** Run with `TF_LOG=DEBUG terraform apply`

---

## Summary: What You Need

**Minimum to start POC:**
```
 Foreman server running (1 server, 2-3 hours to deploy)
 Admin credentials
 3+ bare-metal servers (racked, cabled, IPMI accessible)
 Terraform + Ansible installed on your workstation
 Network infrastructure ready (VLANs, DHCP, PXE)
```

**Don't have Foreman yet?**
 Start with [FOREMAN_SETUP_GUIDE.md](FOREMAN_SETUP_GUIDE.md)

**Have Foreman running?**
 Continue to [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)

---

**Bottom Line:** This POC automates **OS provisioning and configuration** using Terraform + Ansible, but it **requires Foreman infrastructure** to already exist. Budget 2-3 hours to deploy Foreman if starting from scratch, then 90 minutes for the POC itself.

**Total time from zero to working POC: 3-4 hours** ⏱️
