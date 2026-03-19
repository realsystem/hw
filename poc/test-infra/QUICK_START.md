# Quick Start Guide

## Start Test Environment (1 minute)

```bash
# From the poc directory
cd test-infra
./setup.sh
```

**Choose your testing mode:**
- **Option 1**: Ansible testing (PXE server + 3 nodes)
- **Option 2**: Terraform testing (Mock Foreman API + 3 nodes)

See [TERRAFORM_TESTING.md](TERRAFORM_TESTING.md) for complete Terraform testing guide.

## Test 1: SSH to Nodes (30 seconds)

```bash
# SSH to node 1
ssh -p 2301 root@localhost
# Password: testpass

# Inside node:
hostname                           # ceph-osd-r07-u12
/usr/local/bin/hardware-facts.sh   # See simulated hardware
exit
```

## Test 2: Hardware Discovery (1 minute)

```bash
# Get hardware facts from all nodes
docker exec node-01 /usr/local/bin/hardware-facts.sh | jq .
docker exec node-02 /usr/local/bin/hardware-facts.sh | jq .
docker exec node-03 /usr/local/bin/hardware-facts.sh | jq .

# Should show:
# - CPU: 20 cores
# - RAM: 256GB
# - Disks: 12 (1 OS + 11 data)
# - Network interfaces
# - IPMI address
```

## Test 3: Ansible Connectivity (2 minutes)

```bash
# From test-infra directory, go to ansible directory (required for ansible.cfg)
cd ../ansible

# Test connectivity
ansible -i ../test-infra/inventory-sim.yml all -m ping

# Run ad-hoc command
ansible -i ../test-infra/inventory-sim.yml all -a "hostname"

# Go back to test-infra
cd ../test-infra
```

## Test 4: DHCP Server (1 minute)

```bash
# Check DHCP is running
docker exec pxe-server ps aux | grep dnsmasq

# Check DHCP config
docker exec pxe-server cat /etc/dnsmasq.conf

# Watch DHCP logs (live)
docker logs -f pxe-server
# Press Ctrl+C to stop
```

## Test 5: Run Ansible Playbook (5 minutes)

```bash
# From test-infra directory, go to ansible directory (required for ansible.cfg)
cd ../ansible

# Run your actual playbook
ansible-playbook -i ../test-infra/inventory-sim.yml \
  playbooks/ceph_baseline.yml \
  --limit node-01

# This will:
# - Install packages
# - Configure sysctl (where possible in Docker)
# - Set up monitoring
# - Run validation tests

# Go back to test-infra
cd ../test-infra
```

## Test 6: Network Isolation (1 minute)

```bash
# Check node networks
docker exec node-01 ip addr

# Should see:
# - lo: loopback
# - eth0: 172.30.0.100 (provisioning network)

# Test connectivity between nodes
docker exec node-01 ping -c 3 172.30.0.101
docker exec node-01 ping -c 3 172.30.0.110
```

## Common Commands

### View Running Containers
```bash
docker ps
```

### Check Logs
```bash
docker logs pxe-server    # DHCP/DNS/TFTP
docker logs node-01        # Node 1
docker logs node-02        # Node 2
docker logs node-03        # Node 3
```

### Restart Services
```bash
cd test-infra
docker-compose -f docker-compose.simple.yml restart
```

### Enter Container
```bash
docker exec -it node-01 bash
docker exec -it pxe-server bash
```

### Stop Everything
```bash
cd test-infra
docker-compose -f docker-compose.simple.yml down
```

### Clean Start
```bash
cd test-infra
docker-compose -f docker-compose.simple.yml down -v
./setup.sh
```

## What You Can Test

### Works Great
- SSH connectivity
- Ansible playbooks
- Package installation
- Network configuration
- Hardware facts collection
- Service management (limited)

### Partially Works
- DHCP (server runs, but nodes are static)
- sysctl (some parameters fail in Docker)
- systemd (limited in containers)

### Doesn't Work
- PXE netboot (no actual reboot)
- IPMI power control (simulated only)
- Kernel modules
- Real disk I/O

## Troubleshooting

### Can't SSH to nodes
```bash
# Check node is running
docker ps | grep node-

# Check SSH is running
docker exec node-01 ps aux | grep sshd

# Restart SSH
docker exec node-01 bash -c "/usr/sbin/sshd"
```

### Ansible fails
```bash
# Test SSH manually first
ssh -p 2301 root@localhost

# Use verbose mode (from ansible directory)
cd ../ansible
ansible -i ../test-infra/inventory-sim.yml all -m ping -vvv
cd ../test-infra
```

### Docker compose fails
```bash
# Clean everything
docker-compose -f docker-compose.simple.yml down -v

# Check Docker has enough resources
docker info | grep -i memory

# Start again
./setup.sh
```

## Foreman Installation (Bootstrap Host)

This test environment is for Ansible development only. For full deployment with Foreman:

**Install Foreman on your bootstrap host** (not Docker):

```bash
# On Debian 12 bootstrap host
wget https://apt.theforeman.org/pubkey.gpg -O /tmp/foreman.asc
sudo cp /tmp/foreman.asc /etc/apt/trusted.gpg.d/
echo 'deb http://apt.theforeman.org/ bookworm 3.9' | sudo tee /etc/apt/sources.list.d/foreman.list

sudo apt-get update
sudo apt-get install -y foreman-installer
sudo foreman-installer --enable-foreman-plugin-ansible
```

**Then configure Terraform:**

```bash
cd ../terraform/00-provider
cat > terraform.tfvars << EOF
foreman_url      = "https://<bootstrap-host-ip>"
foreman_username = "admin"
foreman_password = "<your-password>"
foreman_insecure = false
EOF

terraform init
terraform apply
```

**Complete guide:** [FOREMAN_SETUP_GUIDE.md](../FOREMAN_SETUP_GUIDE.md)

## Terraform Testing (Option 2)

Test Terraform configurations using the `terraform-coop/foreman` provider against a mock Foreman API.

### Quick Start

```bash
cd test-infra
./setup.sh
# Choose option 2
```

### Test API

```bash
# Check mock Foreman API
curl http://localhost:3000/api/status
# Should return: {"status":"ok","version":"3.9.0"}
```

### Run Terraform

```bash
cd ../terraform/00-provider

# Initialize (downloads foreman provider)
terraform init

# Test connection
terraform plan
terraform apply

# Should output:
# foreman_connection = {
#   server = "http://localhost:3000"
#   username = "admin"
#   architecture = "x86_64"
#   status = "connected"
# }
```

### Create Resources

```bash
cd ../01-foreman-config

# Initialize
terraform init

# Create hostgroups and subnets
terraform plan
terraform apply

# Verify via API
curl -u admin:changeme123 http://localhost:3000/api/v2/hostgroups | jq .
```

**Full guide:** [TERRAFORM_TESTING.md](TERRAFORM_TESTING.md)

## Next Steps

1. Test Ansible playbooks against simulated nodes (Option 1)
2. Test Foreman integration with Terraform (Option 2)
3. Develop new Ansible roles
4. Test DHCP configuration changes
5. Validate hardware discovery logic
6. Practice deployment procedures

Then deploy to real hardware using the same playbooks and Terraform configs!

---

**Environment**: Simulation for development/testing
**Purpose**: Safe testing without real hardware
**Simple Ready**: ~1 minute to start
**Full Ready**: ~15 minutes first run, ~3 minutes after
