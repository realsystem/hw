# Infrastructure Simulation Environment

Docker-based environment for testing Ansible playbooks against simulated bare-metal nodes.

## Purpose

**Use this for:**
- Ansible playbook development and testing
- Terraform configuration testing with mock Foreman API
- Validating infrastructure code before deploying to real hardware
- Learning the provisioning workflow

**NOT for:**
- Running real Foreman (install on bootstrap host - see [FOREMAN_SETUP_GUIDE.md](../FOREMAN_SETUP_GUIDE.md))
- Full PXE boot testing (requires real hardware)
- Production deployment

## Testing Modes

### Option 1: Ansible Testing
- **PXE Server**: dnsmasq for DHCP/DNS/TFTP
- **3 Simulated Nodes**: SSH-accessible containers
- **Purpose**: Test Ansible playbooks and roles

### Option 2: Terraform Testing
- **Mock Foreman API**: Lightweight API server (http://localhost:3000)
- **3 Simulated Nodes**: Same as Option 1
- **Purpose**: Test Terraform provider and resource definitions

## Components

**Simulated Nodes** (both modes):
- node-01 (OSD): localhost:2301 (SSH)
- node-02 (OSD): localhost:2302 (SSH)
- node-03 (MON): localhost:2303 (SSH)

## Quick Start

### 1. Start Environment

```bash
# From the poc directory
cd test-infra
./setup.sh
```

**Choose your mode:**
- **Option 1**: Ansible testing (PXE + nodes) - for playbook development
- **Option 2**: Terraform testing (Mock API + nodes) - for Terraform development

### 2. For Ansible (Option 1)

Test SSH access:

```bash
# SSH to nodes via localhost ports
ssh -p 2301 root@localhost  # node-01 (password: testpass)
ssh -p 2302 root@localhost  # node-02
ssh -p 2303 root@localhost  # node-03
```

### 3. Check Hardware Facts

```bash
# From host
docker exec node-01 /usr/local/bin/hardware-facts.sh | jq .

# Shows simulated hardware:
# - CPU: 20 cores
# - RAM: 256GB
# - Disks: 12 total (1 OS + 11 data)
```

### 4. Test Ansible

```bash
# Test connectivity
cd ../ansible
ansible -i ../test-infra/inventory-sim.yml all -m ping

# Run playbook
ansible-playbook -i ../test-infra/inventory-sim.yml \
  playbooks/ceph_baseline.yml
```

### For Terraform (Option 2)

Test the mock Foreman API:

```bash
# Check API status
curl http://localhost:3000/api/status

# Configure Terraform
cd ../terraform/00-provider
cat > terraform.tfvars << EOF
foreman_hostname = "localhost:3000"
foreman_protocol = "http"
foreman_username = "admin"
foreman_password = "changeme123"
foreman_insecure = "true"
EOF

# Test Terraform
terraform init
terraform plan
terraform apply
```

See [TERRAFORM_TESTING.md](TERRAFORM_TESTING.md) for complete guide.

### 5. Stop Environment

```bash
cd test-infra

# For Ansible mode (Option 1)
docker-compose -f docker-compose.simple.yml down

# For Terraform mode (Option 2)
docker-compose -f docker-compose.terraform.yml down
```

## Architecture

```
┌──────────────────────────────────────────────────┐
│  Your Mac (Host)                                 │
│  ├─ Docker Engine                                │
│  └─ SSH Ports: 2301, 2302, 2303                  │
└──────────────────────────────────────────────────┘
                      |
              ┌───────▼────────┐
              │ provisioning   │
              │ 172.30.0.0/16  │
              │                │
              │ - PXE Server   │
              │   172.30.0.10  │
              │   (DHCP/TFTP)  │
              │                │
              │ - node-01      │
              │   172.30.0.100 │
              │   :2301        │
              │                │
              │ - node-02      │
              │   172.30.0.101 │
              │   :2302        │
              │                │
              │ - node-03      │
              │   172.30.0.110 │
              │   :2303        │
              └────────────────┘
```

## Node Details

### Node 1 (OSD)
- **Container**: node-01
- **Hostname**: ceph-osd-r07-u12
- **MAC**: 52:54:00:aa:bb:01
- **IP**: 172.30.0.100
- **SSH**: localhost:2301 (root / testpass)
- **Simulated Hardware**: 20 cores, 256GB RAM, 12 disks

### Node 2 (OSD)
- **Container**: node-02
- **Hostname**: ceph-osd-r07-u13
- **MAC**: 52:54:00:aa:bb:02
- **IP**: 172.30.0.101
- **SSH**: localhost:2302 (root / testpass)
- **Simulated Hardware**: 20 cores, 256GB RAM, 12 disks

### Node 3 (MON)
- **Container**: node-03
- **Hostname**: ceph-mon-r03-u05
- **MAC**: 52:54:00:aa:bb:10
- **IP**: 172.30.0.110
- **SSH**: localhost:2303 (root / testpass)
- **Simulated Hardware**: 16 cores, 128GB RAM, 2 disks

## Testing Scenarios

### Scenario 1: SSH Access

```bash
# SSH to any node
ssh -p 2301 root@localhost  # password: testpass

# Inside node:
hostname                      # ceph-osd-r07-u12
ip addr                       # Network config
lsblk                         # Disk devices
/usr/local/bin/hardware-facts.sh | jq .  # Hardware info
```

### Scenario 2: Hardware Facts

```bash
# Get simulated hardware from all nodes
docker exec node-01 /usr/local/bin/hardware-facts.sh | jq .
docker exec node-02 /usr/local/bin/hardware-facts.sh | jq .
docker exec node-03 /usr/local/bin/hardware-facts.sh | jq .

# Output shows realistic Supermicro X9 specs:
# - CPU: 20 cores (OSD) or 16 cores (MON)
# - RAM: 256GB (OSD) or 128GB (MON)
# - Disks: 12 (OSD) or 2 (MON)
```

### Scenario 3: Ansible Connectivity

```bash
# Test all nodes
cd ../ansible
ansible -i ../test-infra/inventory-sim.yml all -m ping

# Run ad-hoc commands
ansible -i ../test-infra/inventory-sim.yml all -a "hostname"
ansible -i ../test-infra/inventory-sim.yml all -a "uptime"
```

### Scenario 4: Run Playbooks

```bash
# Run baseline configuration
ansible-playbook -i ../test-infra/inventory-sim.yml \
  playbooks/ceph_baseline.yml

# Run specific roles only
ansible-playbook -i ../test-infra/inventory-sim.yml \
  playbooks/ceph_baseline.yml \
  --tags network,kernel

# Limit to specific nodes
ansible-playbook -i ../test-infra/inventory-sim.yml \
  playbooks/ceph_baseline.yml \
  --limit node-01
```

### Scenario 5: DHCP Server

```bash
# Watch DHCP logs
docker logs -f pxe-server

# Check dnsmasq configuration
docker exec pxe-server cat /etc/dnsmasq.conf

# Test from node (nodes have static IPs in Docker)
docker exec node-01 ping -c 3 172.30.0.10
```

## What Works / Doesn't Work

### Works Great
- SSH access to all nodes
- Ansible playbook execution
- Package installation (apt)
- File management and templates
- Hardware facts collection
- Network connectivity between nodes
- DHCP server (dnsmasq)

### Works With Limitations
- **sysctl**: Kernel parameters fail in Docker (need host access)
  - Config files are created correctly
  - Will work on real bare-metal
  - Playbooks have `ignore_errors: yes`

- **systemd**: Limited in containers
  - Service files created correctly
  - Services can't start in Docker
  - Will work on real bare-metal

- **Timezone**: UTC vs Etc/UTC confusion
  - Doesn't affect functionality
  - Expected Docker limitation

### Doesn't Work
- PXE netboot (nodes don't actually reboot)
- IPMI power control (no real BMC)
- Kernel modules (container limitation)
- Hardware RAID (no real disks)
- I/O schedulers (no real block devices)

## Use Cases

### Perfect For
- Ansible playbook development
- Testing role logic and task ordering
- Validating configurations before deploying to real hardware
- Learning the provisioning workflow
- Testing without hardware dependency

### Not Suitable For
- Full PXE boot testing (use real hardware)
- OS installation (nodes already have Debian)
- Performance benchmarking
- Production deployment
- Foreman testing (install on bootstrap host)

## Troubleshooting

### Can't SSH to Nodes

```bash
# Check nodes are running
docker ps | grep node-

# Check SSH daemon
docker exec node-01 ps aux | grep sshd

# Restart node if needed
docker restart node-01

# Test SSH manually
ssh -p 2301 -o StrictHostKeyChecking=no root@localhost
```

### Ansible Connection Fails

```bash
# Test ping
cd ansible
ansible -i ../test-infra/inventory-sim.yml all -m ping -vvv

# Check inventory file
cat ../test-infra/inventory-sim.yml

# Verify you're in ansible/ directory (for ansible.cfg)
pwd  # Should be /path/to/poc/ansible
```

### Containers Won't Start

```bash
# Check Docker
docker info

# Clean restart
cd test-infra
docker-compose -f docker-compose.simple.yml down -v
./setup.sh  # Choose option 1

# Check logs
docker logs pxe-server
docker logs node-01
```

## Cleanup

```bash
# Stop containers
cd test-infra
docker-compose -f docker-compose.simple.yml down

# Remove volumes (clean state)
docker-compose -f docker-compose.simple.yml down -v

# Remove all (including images)
docker-compose -f docker-compose.simple.yml down --rmi all -v
```

## Files

```
test-infra/
├── setup.sh                    # Start script
├── docker-compose.simple.yml   # Environment definition
├── inventory-sim.yml           # Ansible inventory
├── nodes/
│   ├── Dockerfile.node         # Node image
│   └── hardware-facts.sh       # Hardware simulation
└── config/
    └── dnsmasq.conf            # DHCP/DNS/TFTP config
```

## Next Steps

**For Ansible Testing:**
1. Start environment: `cd test-infra && ./setup.sh`
2. Test SSH: `ssh -p 2301 root@localhost` (password: testpass)
3. Run Ansible: See [QUICK_START.md](QUICK_START.md)
4. Develop and test your playbooks

**For Full Deployment:**
1. Test Ansible in this environment first
2. Install Foreman on bootstrap host: [FOREMAN_SETUP_GUIDE.md](../FOREMAN_SETUP_GUIDE.md)
3. Configure Foreman with Terraform: `terraform/00-provider/`
4. Deploy to real hardware

**Documentation:**
- [QUICK_START.md](QUICK_START.md) - Step-by-step testing guide
- [TESTING.md](TESTING.md) - What works, limitations, workflow
- [README.md](README.md) - This file

---

**Ready in**: ~1 minute
**Purpose**: Ansible testing without real hardware
**Last Updated**: 2026-03-19
