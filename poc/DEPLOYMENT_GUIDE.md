# Deployment Guide

Complete step-by-step guide to deploy bare-metal servers using Terraform + Foreman + Ansible.

---

## Prerequisites

Before starting:

1. **Foreman server** running with DHCP/TFTP configured
2. **Server inventory** defined in `inventory.yml`
3. **Bootstrap host** with Terraform, Ansible, and ipmitool installed
4. **Network** configured (DHCP, DNS, Internet access)

---

## Quick Start

```bash
# 1. Configure credentials
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Add Foreman URL, credentials, SSH keys

# 2. Update inventory
vim inventory.yml  # Add your servers, networks, IPMI credentials

# 3. Deploy everything
./deploy.sh
```

That's it! The script will:
- Configure Foreman (hostgroups, subnets, partition tables)
- Power on servers via IPMI
- Wait for hardware discovery
- Provision OS on all nodes
- Configure nodes with Ansible
- Run validation tests

**Timeline**: ~60-90 minutes for 6 nodes

---

## Detailed Step-by-Step

### Step 1: Initial Configuration

#### 1.1 Configure Terraform Variables

```bash
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

Required values:
```hcl
foreman_url      = "https://foreman.example.com"  # Your Foreman server
foreman_username = "admin"
foreman_password = "your-password"

ssh_public_key = "ssh-rsa AAAAB3..."  # From ~/.ssh/id_rsa.pub
```

#### 1.2 Configure Server Inventory

Edit `inventory.yml` with your server details:

```yaml
servers:
  - hostname: ceph-osd-r07-u12
    role: osd  # or mon
    rack: 7
    unit: 12
    ipmi:
      address: 10.20.7.12
      username: ADMIN
      password: ADMIN
    network:
      provisioning_mac: "00:25:90:e3:6c:4a"  # MAC address for PXE
      management_ip: 10.10.7.12
      provisioning_ip: 10.50.7.12
      ceph_public_ip: 10.20.7.12
      ceph_cluster_ip: 10.30.7.12
    hardware:
      cpu_cores: 20
      ram_gb: 256
      disks: 12
```

Repeat for all servers.

#### 1.3 Verify Prerequisites

```bash
./deploy.sh check
```

This checks:
-  Terraform installed
-  Ansible installed
-  ipmitool available
-  terraform.tfvars exists
-  inventory.yml exists

---

### Step 2: Deploy Foreman Configuration

#### 2.1 Initialize and Plan

```bash
cd terraform/01-foreman-config
terraform init
terraform plan -var-file=../../terraform.tfvars
```

This creates:
- Provisioning and management subnets
- Partition tables for OSD and MON nodes
- Hostgroups (ceph-osd-nodes, ceph-mon-nodes)

#### 2.2 Apply Configuration

```bash
terraform apply -var-file=../../terraform.tfvars -auto-approve
```

Expected output:
```
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

hostgroups = {
  "mon" = {
    "id" = 42
    "name" = "Ceph MON Nodes"
  }
  "osd" = {
    "id" = 41
    "name" = "Ceph OSD Nodes"
  }
}
```

#### 2.3 Verify in Foreman UI

1. Open Foreman: `https://foreman.example.com`
2. Navigate to **Configure  Host Groups**
3. Verify hostgroups created
4. Navigate to **Infrastructure  Subnets**
5. Verify networks configured

---

### Step 3: Provision Nodes

#### 3.1 Initialize Node Provisioning

```bash
cd ../02-node-provision
terraform init
terraform plan -var-file=../../terraform.tfvars
```

#### 3.2 Power On Servers

The Terraform apply will:
1. Power on servers via IPMI
2. Servers boot to PXE
3. Load discovery image from Foreman
4. Report hardware facts to Foreman

```bash
terraform apply -var-file=../../terraform.tfvars
```

You'll see:
```
[10.20.7.12] Executing action: on
[10.20.7.12] Boot device set to PXE
[10.20.7.12] Power on command sent
...
```

#### 3.3 Wait for Discovery

The script will pause:
```
============================================
Servers are booting for discovery...
============================================

Please verify in Foreman UI:
  Hosts -> Discovered Hosts

Expected 6 servers:
  - ceph-osd-r07-u12 (MAC: 00:25:90:e3:6c:4a)
  - ceph-osd-r07-u13 (MAC: 00:25:90:e3:6c:4b)
  ...

Press ENTER when all servers are discovered...
```

**In Foreman UI:**
1. Navigate to **Hosts  Discovered Hosts**
2. Wait for all servers to appear (5-10 minutes)
3. Verify MAC addresses match inventory
4. Press ENTER in terminal

#### 3.4 OS Installation

Terraform will now:
1. Create Foreman hosts from discovered nodes
2. Assign to hostgroups
3. Set `build=true` (triggers OS install)
4. Wait for SSH to become available

```
foreman_host.ceph_osd["ceph-osd-r07-u12"]: Creating...
foreman_host.ceph_osd["ceph-osd-r07-u12"]: Still creating... [5m0s elapsed]
...
foreman_host.ceph_osd["ceph-osd-r07-u12"]: Creation complete [15m23s]
```

**Timeline**: 15-20 minutes per node (parallel)

#### 3.5 Verify SSH Access

Once provisioning completes:
```bash
# Test SSH to first node
ssh root@10.10.7.12 "hostname && cat /etc/debian_version"
```

Expected:
```
ceph-osd-r07-u12
12.5
```

#### 3.6 Check Ansible Inventory

```bash
cat ../../ansible/inventory/hosts.yml
```

Should show:
```yaml
all:
  children:
    ceph_osd:
      hosts:
        ceph-osd-r07-u12:
          ansible_host: 10.10.7.12
          ...
```

---

### Step 4: Configure Nodes with Ansible

#### 4.1 Test Ansible Connectivity

```bash
cd ../../ansible
ansible -i inventory/hosts.yml all -m ping
```

Expected:
```
ceph-osd-r07-u12 | SUCCESS => {
    "ping": "pong"
}
...
```

#### 4.2 Run Baseline Configuration

```bash
ansible-playbook -i inventory/hosts.yml playbooks/ceph_baseline.yml
```

This applies:
- **common**: Basic packages, timezone
- **network**: TCP tuning, MTU 9000, sysctl
- **kernel**: THP disable, vm.swappiness, CPU governor
- **storage**: I/O schedulers, read-ahead
- **time**: Chrony NTP synchronization
- **monitoring**: Prometheus node_exporter

**Timeline**: 10-15 minutes

Expected output:
```
PLAY [Configure Ceph-ready baseline on all nodes] ****

TASK [common : Update apt cache] ****
ok: [ceph-osd-r07-u12]
...

PLAY RECAP ****
ceph-osd-r07-u12 : ok=28 changed=15 unreachable=0 failed=0
ceph-osd-r07-u13 : ok=28 changed=15 unreachable=0 failed=0
...
```

---

### Step 5: Validate Configuration

#### 5.1 Run Validation Tests

```bash
ansible-playbook -i inventory/hosts.yml playbooks/validate.yml
```

Tests performed:
-  Transparent Huge Pages disabled
-  vm.swappiness = 10
-  Network tuning applied
-  Time synchronization working
-  Node exporter running
-  Data disks available (OSD nodes)

Expected output:
```
TASK [Validate THP disabled] ****
ok: [ceph-osd-r07-u12] => {
    "msg": " THP is disabled"
}

TASK [Validate swappiness] ****
ok: [ceph-osd-r07-u12] => {
    "msg": " vm.swappiness = 10"
}
...

TASK [Generate validation summary] ****
ok: [ceph-osd-r07-u12] => {
    "msg": "=====================================\n
            Validation Summary for ceph-osd-r07-u12\n
            =====================================\n
             Transparent Huge Pages: Disabled\n
             Kernel Tuning: Applied\n
             Network Tuning: Applied\n
             Time Synchronization: Working\n
             Monitoring: Running\n
             Data Disks: 12 available\n
            \n
            Node is READY for Ceph deployment\n
            ====================================="
}
```

#### 5.2 Manual Verification

SSH to a node and verify:

```bash
ssh root@ceph-osd-r07-u12

# Check THP
cat /sys/kernel/mm/transparent_hugepage/enabled
# Expected: [never]

# Check sysctl
sysctl vm.swappiness
# Expected: vm.swappiness = 10

# Check network tuning
sysctl net.core.rmem_max
# Expected: net.core.rmem_max = 134217728

# Check time sync
chronyc tracking
# Expected: Leap status: Normal

# Check node exporter
curl -s http://localhost:9100/metrics | head -20
# Expected: Prometheus metrics

# Check data disks
lsblk -d | grep -v sda
# Expected: List of 10+ data disks
```

---

## Automated Deployment

Instead of manual steps, use the automated script:

### Full Deployment

```bash
./deploy.sh
```

Runs all phases automatically.

### Individual Phases

```bash
# Phase 1 only
./deploy.sh foreman

# Phase 2 only
./deploy.sh provision

# Phase 3 only
./deploy.sh configure

# Phase 4 only
./deploy.sh validate
```

---

## Troubleshooting

### Issue: Terraform Provider Error

**Symptom:**
```
Error: Failed to query Foreman API
```

**Solution:**
```bash
# Test Foreman connectivity
curl -k https://foreman.example.com/api/status

# Verify credentials in terraform.tfvars
vim terraform.tfvars
```

### Issue: Discovery Timeout

**Symptom:** Servers don't appear in Foreman after 15 minutes

**Solution:**
```bash
# Check IPMI power status
ipmitool -I lanplus -H 10.20.7.12 -U ADMIN -P ADMIN chassis power status

# Check server console
ipmitool -I lanplus -H 10.20.7.12 -U ADMIN -P ADMIN sol activate

# Verify DHCP/TFTP in Foreman
# Infrastructure  Smart Proxies  Check DHCP/TFTP status
```

### Issue: SSH Timeout

**Symptom:**
```
Error: Timeout waiting for ceph-osd-r07-u12
```

**Solution:**
```bash
# Check if server finished OS install
ipmitool -I lanplus -H 10.20.7.12 -U ADMIN -P ADMIN sol activate

# Verify network connectivity
ping 10.10.7.12

# Check Foreman build status
# Hosts  All Hosts  Find node  Check build status
```

### Issue: Ansible Unreachable

**Symptom:**
```
ceph-osd-r07-u12 | UNREACHABLE!
```

**Solution:**
```bash
# Verify SSH key
ssh root@10.10.7.12
# Should not ask for password

# Check SSH key in terraform.tfvars
cat terraform.tfvars | grep ssh_public_key

# Verify key matches
cat ~/.ssh/id_rsa.pub
```

### Issue: Validation Failures

**Symptom:**
```
FAILED: THP is not disabled
```

**Solution:**
```bash
# Re-run Ansible configuration
ansible-playbook -i inventory/hosts.yml playbooks/ceph_baseline.yml --tags kernel

# Reboot if needed
ansible -i inventory/hosts.yml all -a "reboot"

# Re-validate
ansible-playbook -i inventory/hosts.yml playbooks/validate.yml
```

---

## Cleanup

### Destroy All Resources

```bash
./deploy.sh clean
```

This will:
1. Destroy provisioned hosts in Foreman
2. Destroy Foreman configuration
3. Power off servers

### Manual Cleanup

```bash
# Destroy nodes
cd terraform/02-node-provision
terraform destroy -var-file=../../terraform.tfvars -auto-approve

# Destroy Foreman config
cd ../01-foreman-config
terraform destroy -var-file=../../terraform.tfvars -auto-approve

# Power off servers
cd ../../scripts
./ipmi-power.sh 10.20.7.12 ADMIN ADMIN off
./ipmi-power.sh 10.20.7.13 ADMIN ADMIN off
...
```

---

## Next Steps

After successful deployment:

1. **Review Results**
   ```bash
   ansible -i ansible/inventory/hosts.yml all -m shell -a "hostname && cat /etc/debian_version"
   ```

2. **Deploy Ceph**
   ```bash
   # Use ceph-ansible with generated inventory
   cd ../ceph-ansible
   ansible-playbook -i ../hw/poc/ansible/inventory/hosts.yml site.yml
   ```

3. **Verify Ceph Cluster**
   ```bash
   ssh root@ceph-osd-r07-u12 "ceph -s"
   ```

---

## Timeline Summary

| Phase | Duration | Parallel? |
|-------|----------|-----------|
| 1. Foreman Config | 5 min | No |
| 2. Discovery | 10 min | Yes |
| 3. OS Install | 20 min | Yes (all nodes) |
| 4. Ansible Config | 15 min | Yes |
| 5. Validation | 5 min | No |
| **Total** | **55-60 min** | **For 6 nodes** |

Scales to 100+ nodes with same timeline (parallel provisioning).

---

## Success Criteria

Deployment is successful when:

-  All nodes provisioned (6/6)
-  All SSH connections working
-  All validation tests passing (100%)
-  Ansible inventory generated
-  Nodes in lifecycle state: READY_CEPH

**Ready for Ceph deployment!**
