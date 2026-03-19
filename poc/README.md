# Terraform + Foreman + Ansible POC

## Overview

This POC demonstrates a complete bare-metal provisioning workflow using:
- **Terraform**: Infrastructure as Code, orchestrates Foreman resources
- **Foreman**: PXE boot, OS installation, hardware discovery
- **Ansible**: Post-provision configuration (Ceph-ready baseline)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  1. Foreman Control Plane (pre-deployed)                    │
│     - Already running and configured                        │
│     - DHCP/TFTP/HTTP boot services active                   │
└─────────────────────────────────────────────────────────────┘
                            
┌─────────────────────────────────────────────────────────────┐
│  2. Terraform Configuration                                 │
│     a. Define Foreman resources (hostgroups, subnets)       │
│     b. Query discovered nodes                               │
│     c. Trigger OS provisioning                              │
│     d. Wait for completion                                  │
└─────────────────────────────────────────────────────────────┘
                            
┌─────────────────────────────────────────────────────────────┐
│  3. Ansible Configuration                                   │
│     - Network tuning (bonding, sysctl)                      │
│     - Kernel parameters (THP, I/O schedulers)               │
│     - Monitoring (node_exporter)                            │
│     - Validation tests                                      │
└─────────────────────────────────────────────────────────────┘
                            
┌─────────────────────────────────────────────────────────────┐
│  4. Output: Ceph-Ready Nodes                                │
│     - Debian 12 installed                                   │
│     - Networks configured                                   │
│     - Optimized for storage workloads                       │
│     - Ready for ceph-ansible deployment                     │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

**Critical**: Foreman must be deployed before starting this POC.

**Required**:
- Foreman 3.7+ with PostgreSQL and Smart Proxy (DHCP/TFTP)
- Terraform 1.6+ and Ansible 2.15+ on client
- 3+ bare-metal servers with IPMI

See [PREREQUISITES.md](PREREQUISITES.md) for detailed checklist and [FOREMAN_SETUP_GUIDE.md](FOREMAN_SETUP_GUIDE.md) if you need to deploy Foreman.

## Quick Start

### Step 1: Configure Credentials

```bash
# Copy example config
cp terraform.tfvars.example terraform.tfvars

# Edit with your Foreman credentials
vim terraform.tfvars
```

```hcl
# terraform.tfvars
foreman_url      = "https://foreman.example.com"
foreman_username = "admin"
foreman_password = "changeme"

# SSH key for provisioned nodes
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E..."
```

### Step 2: Initialize Terraform

```bash
cd terraform/
terraform init
```

### Step 3: Deploy Foreman Configuration

```bash
# Create hostgroups, subnets, templates
cd 01-foreman-config
terraform plan
terraform apply

# Output:
# foreman_hostgroup.ceph_osd: Creating...
# foreman_hostgroup.ceph_mon: Creating...
# foreman_subnet.provisioning: Creating...
```

### Step 4: Discover Nodes

Power on target servers via IPMI (they'll PXE boot into discovery mode):

```bash
# Manually power on nodes
cd ../../scripts/
./ipmi-power-on.sh 10.20.7.12 10.20.7.13 10.20.7.14

# Or let Terraform do it
cd ../terraform/02-hardware-discovery
terraform apply
```

Wait 5-10 minutes for hardware discovery to complete.

### Step 5: Provision Nodes

```bash
cd ../03-node-provision
terraform plan   # Shows discovered nodes to provision
terraform apply  # Triggers OS installation

# Monitor progress
watch -n 10 'terraform output -json provision_status | jq'
```

Provisioning takes 15-20 minutes per node.

### Step 6: Configure Nodes (Ansible)

```bash
cd ../04-post-config
terraform apply  # Runs Ansible playbooks

# Or run Ansible directly
cd ../../ansible/
ansible-playbook -i inventory/terraform.py playbooks/ceph_baseline.yml
```

### Step 7: Validate

```bash
# Check node states
cd ../terraform/03-node-provision
terraform output node_inventory

# SSH to a node
ssh root@ceph-osd-r07-u12

# Verify configuration
/usr/local/bin/validate-ceph-ready.sh
```

## Directory Structure

```
poc/
├── README.md                    # This file
├── terraform/
│   ├── 00-provider/             # Foreman provider setup
│   ├── 01-foreman-config/       # Hostgroups, subnets, templates
│   ├── 02-hardware-discovery/   # IPMI automation for discovery
│   ├── 03-node-provision/       # Trigger OS installation
│   ├── 04-post-config/          # Run Ansible via Terraform
│   └── modules/                 # Reusable Terraform modules
├── ansible/
│   ├── inventory/
│   │   ├── terraform.py         # Dynamic inventory from Terraform
│   │   └── group_vars/
│   ├── playbooks/
│   │   ├── ceph_baseline.yml    # Main playbook
│   │   └── validate.yml         # Validation tests
│   └── roles/
│       ├── network/             # Network configuration
│       ├── kernel/              # Kernel tuning
│       ├── storage/             # I/O schedulers
│       └── monitoring/          # Prometheus exporters
├── scripts/
│   ├── ipmi-power-on.sh         # IPMI helper scripts
│   ├── check-provision.sh       # Monitor provisioning
│   └── cleanup.sh               # Reset POC environment
└── docs/
    ├── foreman-setup.md         # Foreman prerequisites
    └── troubleshooting.md       # Common issues
```

## Technical Details

### Terraform Phases
1. **Foreman Config**: Hostgroups, subnets, partition tables
2. **Discovery**: Power on servers, wait for Foreman discovery
3. **Provisioning**: Assign hosts, trigger OS install, wait for SSH
4. **Post-Config**: Generate Ansible inventory, run playbooks, validate

### Ansible Roles
- **network**: Bonding, MTU 9000, TCP tuning
- **kernel**: sysctl, THP disable, CPU governor
- **storage**: I/O schedulers, disk layout
- **monitoring**: Prometheus node_exporter

See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed workflow and code examples.

## Expected Results

**Timeline**: 15-20 min per node (OS install) + 10-15 min (configuration)
**Success Rate**: 99%+ with validated hardware
**Output**: Ceph-ready nodes with all validation tests passing

See [POC_SUMMARY.md](POC_SUMMARY.md) for detailed metrics and results.

## Troubleshooting

### Provisioning Stuck

```bash
# Check Foreman build status
hammer host list --search "build = true"

# View installation logs (serial console)
cd scripts/
./ipmi-sol-capture.sh 10.20.7.12

# Check DHCP leases
ssh foreman-proxy.example.com
cat /var/lib/dhcp/dhcpd.leases | grep 00:25:90:aa:bb:cc
```

### Terraform Errors

```bash
# Re-initialize provider
terraform init -upgrade

# Enable debug logging
export TF_LOG=DEBUG
terraform apply

# Force unlock (if state locked)
terraform force-unlock <lock-id>
```

### Ansible Failures

```bash
# Test connectivity
ansible -i inventory/terraform.py all -m ping

# Run with verbose output
ansible-playbook -i inventory/terraform.py playbooks/ceph_baseline.yml -vvv

# Run specific role only
ansible-playbook -i inventory/terraform.py playbooks/ceph_baseline.yml --tags network
```

## Next Steps

After POC validation:

1. **Scale testing**: Increase node count to 10, 50, 100
2. **HA setup**: Deploy PostgreSQL Patroni, multiple Foreman instances
3. **CI/CD integration**: GitLab CI pipeline for Terraform apply
4. **Monitoring**: Integrate with Prometheus + Grafana
5. **Production rollout**: Follow full implementation plan

## Documentation

- [Foreman Provider Docs](https://registry.terraform.io/providers/terraform-coop/foreman/latest/docs)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Full Architecture](../docs/)

## Support

Issues? Check:
1. [Troubleshooting Guide](docs/troubleshooting.md)
2. [Foreman Community](https://community.theforeman.org/)
3. [Terraform Forums](https://discuss.hashicorp.com/c/terraform-core)

---

**POC Status**:  Ready for deployment
**Last Updated**: 2026-03-18
**Tested On**: Foreman 3.7, Terraform 1.6.6, Ansible 2.15
