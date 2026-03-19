# Path Reference Guide

Quick reference for navigating between directories in this project.

## Directory Structure

```
hw/poc/
├── ansible/              # Ansible playbooks and roles
│   ├── playbooks/
│   ├── roles/
│   └── ansible.cfg       # Required for roles_path
├── terraform/            # Terraform configurations
│   ├── 00-provider/
│   ├── 01-foreman-config/
│   └── 02-node-provision/
├── test-infra/           # Docker test environment
│   ├── setup.sh
│   ├── inventory-sim.yml
│   └── docker-compose.*.yml
└── scripts/              # Helper scripts
```

## Starting Points

### From poc/ (root)

```bash
# Start test environment
cd test-infra
./setup.sh

# Run Ansible
cd ansible
ansible-playbook -i ../test-infra/inventory-sim.yml playbooks/ceph_baseline.yml

# Run Terraform
cd terraform/00-provider
terraform init && terraform plan
```

### From test-infra/

```bash
# You are here after running: cd test-infra

# Run Ansible
cd ../ansible
ansible -i ../test-infra/inventory-sim.yml all -m ping
cd ../test-infra  # back to test-infra

# Run Terraform
cd ../terraform/00-provider
terraform plan
cd ../../test-infra  # back to test-infra

# Stop environment
docker-compose -f docker-compose.simple.yml down
```

### From ansible/

```bash
# You are here after running: cd ansible

# Run playbooks (ansible.cfg required here!)
ansible-playbook -i ../test-infra/inventory-sim.yml playbooks/ceph_baseline.yml

# Test connectivity
ansible -i ../test-infra/inventory-sim.yml all -m ping

# Go to other directories
cd ../terraform/00-provider  # to Terraform
cd ../test-infra            # to test environment
cd ../poc                    # back to root
```

### From terraform/00-provider/

```bash
# You are here after running: cd terraform/00-provider

# Run Terraform
terraform init
terraform plan
terraform apply

# Go to config directory
cd ../01-foreman-config
terraform plan

# Go to other directories
cd ../../ansible           # to Ansible
cd ../../test-infra        # to test environment
cd ../../                  # back to poc root
```

## Common Navigation Patterns

### Test Ansible → Test Terraform

```bash
# Start in poc/
cd test-infra
./setup.sh  # Choose option 1

# Test Ansible
cd ../ansible
ansible-playbook -i ../test-infra/inventory-sim.yml playbooks/ceph_baseline.yml

# Switch to Terraform testing
cd ../test-infra
docker-compose -f docker-compose.simple.yml down
./setup.sh  # Choose option 2

# Test Terraform
cd ../terraform/00-provider
terraform init && terraform plan
```

### Full Workflow

```bash
# 1. Start from poc/ root
cd test-infra

# 2. Start test environment
./setup.sh  # Choose option 1 for Ansible

# 3. Test Ansible
cd ../ansible
ansible -i ../test-infra/inventory-sim.yml all -m ping
ansible-playbook -i ../test-infra/inventory-sim.yml playbooks/ceph_baseline.yml

# 4. Stop and restart for Terraform
cd ../test-infra
docker-compose -f docker-compose.simple.yml down
./setup.sh  # Choose option 2 for Terraform

# 5. Test Terraform
cd ../terraform/00-provider
terraform init
terraform plan
terraform apply

# 6. Create resources
cd ../01-foreman-config
terraform init
terraform plan
terraform apply

# 7. Clean up
cd ../../test-infra
docker-compose -f docker-compose.terraform.yml down
```

## Important Notes

### Ansible Directory Requirement

**You must run ansible commands from the `ansible/` directory** because `ansible.cfg` sets:
```ini
roles_path = ./roles
```

If you run from anywhere else, Ansible won't find the roles.

✅ **Correct:**
```bash
cd poc/ansible
ansible-playbook -i ../test-infra/inventory-sim.yml playbooks/ceph_baseline.yml
```

❌ **Wrong:**
```bash
cd poc
ansible-playbook -i test-infra/inventory-sim.yml ansible/playbooks/ceph_baseline.yml
# Error: roles not found
```

### Terraform Variable Files

Terraform reads `terraform.tfvars` from the current directory:

✅ **Correct:**
```bash
cd terraform/00-provider
terraform plan  # Reads ./terraform.tfvars
```

❌ **Wrong:**
```bash
cd terraform
terraform plan -chdir=00-provider  # Won't find terraform.tfvars
```

## Quick Commands by Location

| Current Dir | Command | Purpose |
|-------------|---------|---------|
| `poc/` | `cd test-infra && ./setup.sh` | Start test environment |
| `test-infra/` | `cd ../ansible` | Go to Ansible |
| `test-infra/` | `cd ../terraform/00-provider` | Go to Terraform |
| `ansible/` | `ansible-playbook -i ../test-infra/inventory-sim.yml playbooks/ceph_baseline.yml` | Run playbook |
| `terraform/00-provider/` | `terraform plan` | Test provider |
| `terraform/01-foreman-config/` | `terraform apply` | Create resources |

---

**Always know where you are**: Use `pwd` to check your current directory.
