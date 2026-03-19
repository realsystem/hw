# Docker Test Environment

Test the Ansible configuration locally using Docker containers instead of real bare-metal servers.

## What This Tests

 **Ansible playbooks** - Verify playbook syntax and execution
 **Package installation** - Test apt packages install correctly
 **Configuration files** - Verify templates and file creation
 **Basic validation** - Test simple validation checks

 **Limitations** (Docker vs Bare-Metal):
- No real IPMI control
- No PXE boot
- No Foreman integration
- Some kernel parameters (THP, CPU governor) won't work in containers
- Limited systemd functionality

## Prerequisites

- Docker Desktop installed and running
- (Optional) sshpass for automated SSH: `brew install hudochenkov/sshpass/sshpass`

## Quick Start

### 1. Start Test Environment

```bash
cd test
./setup-test-env.sh
```

This creates 3 Docker containers:
- `test-osd-01` (172.20.0.10)
- `test-osd-02` (172.20.0.11)
- `test-mon-01` (172.20.0.20)

### 2. Test Ansible Connectivity

```bash
cd ..  # Back to poc/
ansible -i test/inventory-test.yml all -m ping
```

Expected:
```
test-osd-01 | SUCCESS => {
    "ping": "pong"
}
test-osd-02 | SUCCESS => {
    "ping": "pong"
}
test-mon-01 | SUCCESS => {
    "ping": "pong"
}
```

### 3. Run Test Playbook

```bash
ansible-playbook -i test/inventory-test.yml test/test-playbook.yml
```

This tests:
- Package installation
- Timezone configuration
- Sysctl parameters (Docker-safe subset)
- Basic validation

### 4. Test Individual Roles

Test specific roles from the main playbooks:

```bash
# Test common role
ansible-playbook -i test/inventory-test.yml ansible/playbooks/ceph_baseline.yml --tags common

# Test network role (some features limited in Docker)
ansible-playbook -i test/inventory-test.yml ansible/playbooks/ceph_baseline.yml --tags network

# Test time role
ansible-playbook -i test/inventory-test.yml ansible/playbooks/ceph_baseline.yml --tags time

# Test monitoring role
ansible-playbook -i test/inventory-test.yml ansible/playbooks/ceph_baseline.yml --tags monitoring
```

### 5. Test Ad-Hoc Commands

```bash
# Check hostname
ansible -i test/inventory-test.yml all -a "hostname"

# Check Debian version
ansible -i test/inventory-test.yml all -a "cat /etc/debian_version"

# Check installed packages
ansible -i test/inventory-test.yml all -a "dpkg -l | grep vim"

# Check sysctl
ansible -i test/inventory-test.yml all -a "sysctl vm.swappiness"
```

### 6. SSH to Containers Manually

```bash
# Using sshpass
sshpass -p testpass ssh -o StrictHostKeyChecking=no root@172.20.0.10

# Or set up key-based auth
ssh-copy-id -o StrictHostKeyChecking=no root@172.20.0.10
# Then: ssh root@172.20.0.10
```

## Cleanup

```bash
cd test
docker-compose down

# Remove volumes too
docker-compose down -v
```

## Troubleshooting

### Containers Won't Start

```bash
# Check Docker is running
docker info

# Check logs
docker-compose logs

# Restart
docker-compose restart
```

### SSH Connection Refused

```bash
# Check container is running
docker ps

# Check SSH is running in container
docker exec test-osd-01 ps aux | grep sshd

# Restart SSH
docker exec test-osd-01 bash -c "/usr/sbin/sshd"
```

### Ansible Can't Connect

```bash
# Test with verbose output
ansible -i test/inventory-test.yml all -m ping -vvv

# Test SSH directly
sshpass -p testpass ssh -o StrictHostKeyChecking=no root@172.20.0.10 "echo test"
```

## What Each Role Does in Docker

###  Works Well
- **common**: Package installation, timezone
- **network**: Some sysctl (network tuning)
- **time**: Chrony installation (sync won't work, but package installs)
- **monitoring**: Node exporter installation

###  Partial Support
- **kernel**: Some sysctl works, THP and CPU governor don't
- **storage**: Limited (containers don't have real disks)

###  Doesn't Work
- IPMI power control
- PXE boot simulation
- Real disk I/O scheduler changes
- Full systemd functionality

## Example Test Session

```bash
# 1. Start environment
cd test
./setup-test-env.sh

# 2. Test connectivity
cd ..
ansible -i test/inventory-test.yml all -m ping

# 3. Run simplified test
ansible-playbook -i test/inventory-test.yml test/test-playbook.yml

# 4. Test specific role
ansible-playbook -i test/inventory-test.yml ansible/playbooks/ceph_baseline.yml --tags common

# 5. Check results
ansible -i test/inventory-test.yml all -a "dpkg -l | wc -l"

# 6. Cleanup
cd test
docker-compose down
```

## Files

- `docker-compose.yml` - Container definitions
- `inventory-test.yml` - Ansible inventory for test containers
- `setup-test-env.sh` - Setup script
- `test-playbook.yml` - Docker-compatible test playbook
- `README.md` - This file

## Benefits

- **Fast iteration**: Test changes in seconds
- **Safe**: No risk to real hardware
- **Reproducible**: Same environment every time
- **No infrastructure**: Just Docker on your laptop
- **Cost effective**: No cloud resources needed

## Limitations vs Real Environment

| Feature | Docker Test | Real Bare-Metal |
|---------|-------------|-----------------|
| Ansible playbooks |  Full |  Full |
| Package installation |  Full |  Full |
| File/template creation |  Full |  Full |
| Network sysctl |  Partial |  Full |
| Kernel parameters |  Partial |  Full |
| THP disable |  No |  Full |
| Disk I/O scheduling |  No |  Full |
| IPMI control |  No |  Full |
| PXE boot |  No |  Full |

## Recommended Workflow

1. **Develop locally** with Docker test environment
2. **Test syntax** and basic functionality
3. **Iterate quickly** on playbook changes
4. **Deploy to real** bare-metal for full testing
5. **Use Docker** for CI/CD pipeline testing

---

**Use this to validate Ansible configuration before deploying to real hardware!**
