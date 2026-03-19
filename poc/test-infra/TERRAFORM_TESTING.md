# Terraform Testing with Mock Foreman API

## Overview

Test Terraform configurations against a lightweight mock Foreman API using the `terraform-coop/foreman` provider.

**What this provides:**
- Mock Foreman API server at http://localhost:3000
- 3 simulated nodes (same as Ansible testing)
- Test Terraform provider and resource definitions
- Validate infrastructure-as-code structure

**What this doesn't provide:**
- Real PXE boot or OS installation
- Actual Foreman Smart Proxy features
- Production-ready deployment

## Quick Start

### 1. Start Environment

```bash
# From the poc directory
cd test-infra
./setup.sh
# Choose option 2 (Terraform testing)
```

This starts:
- Mock Foreman API on http://localhost:3000
- 3 simulated nodes on 172.35.0.100-110

### 2. Test Foreman API

```bash
# Check API is running
curl http://localhost:3000/api/status

# Should return:
# {"status":"ok","version":"3.9.0","api_version":2}

# Test authentication
curl -u admin:changeme123 http://localhost:3000/api/v2/architectures | jq .
```

### 3. Initialize Terraform

```bash
cd ../terraform/00-provider

# Initialize (downloads the foreman provider)
terraform init
```

### 4. Test Provider Connection

```bash
# Plan (should connect to mock API)
terraform plan

# Apply (tests connection)
terraform apply

# Should output:
# foreman_connection = {
#   server = "http://localhost:3000"
#   username = "admin"
#   architecture = "x86_64"
#   status = "connected"
# }
```

### 5. Create Foreman Resources

```bash
cd ../01-foreman-config

# Initialize
terraform init

# Plan (shows resources to create)
terraform plan

# Apply (creates hostgroups, subnets in mock API)
terraform apply
```

### 6. Verify Resources

```bash
# Check via API
curl -u admin:changeme123 http://localhost:3000/api/v2/hostgroups | jq .
curl -u admin:changeme123 http://localhost:3000/api/v2/subnets | jq .

# Check Terraform state
terraform state list
terraform show
```

## Provider Configuration

The `terraform-coop/foreman` provider is configured as follows:

```hcl
terraform {
  required_providers {
    foreman = {
      source  = "terraform-coop/foreman"
      version = ">= 0.1"
    }
  }
}

provider "foreman" {
  server_hostname = "localhost:3000"
  server_protocol = "http"

  client_username      = "admin"
  client_password      = "changeme123"
  client_tls_insecure  = "true"

  provider_loglevel = "INFO"
  provider_logfile  = "terraform-provider-foreman.log"
}
```

## Mock API Endpoints

The mock API supports:

### Status (no auth)
- `GET /api/status`

### Architectures
- `GET /api/v2/architectures`

### Operating Systems
- `GET /api/v2/operatingsystems`

### Hostgroups
- `GET /api/v2/hostgroups`
- `POST /api/v2/hostgroups`
- `GET /api/v2/hostgroups/:id`
- `PUT /api/v2/hostgroups/:id`
- `DELETE /api/v2/hostgroups/:id`

### Subnets
- `GET /api/v2/subnets`
- `POST /api/v2/subnets`
- `GET /api/v2/subnets/:id`
- `PUT /api/v2/subnets/:id`
- `DELETE /api/v2/subnets/:id`

### Hosts
- `GET /api/v2/hosts`
- `POST /api/v2/hosts`
- `GET /api/v2/hosts/:id`
- `PUT /api/v2/hosts/:id`
- `DELETE /api/v2/hosts/:id`
- `PUT /api/v2/hosts/:id/power`

## Testing Workflow

### Test 1: Provider Initialization

```bash
cd terraform/00-provider
terraform init
# Downloads terraform-coop/foreman provider

terraform apply
# Tests connection to mock API
```

### Test 2: Create Hostgroups

```bash
cd ../01-foreman-config
terraform init
terraform plan
# Shows hostgroups to create

terraform apply
# Creates resources in mock API
```

### Test 3: Verify State

```bash
# Check Terraform state
terraform state list
# Should show:
# - foreman_hostgroup.ceph_osd
# - foreman_hostgroup.ceph_mon
# - foreman_subnet.provisioning
# - foreman_subnet.management

# Check mock API
curl -u admin:changeme123 http://localhost:3000/api/v2/hostgroups | jq '.results[] | {id, name}'
```

### Test 4: Update Resources

```bash
# Edit resource attributes in main.tf
# Run plan to see changes
terraform plan

# Apply updates
terraform apply
```

### Test 5: Destroy Resources

```bash
terraform destroy
# Removes all created resources
```

## Example Terraform Code

```hcl
# Create a hostgroup
resource "foreman_hostgroup" "ceph_osd" {
  name               = "Ceph OSD Nodes"
  architecture_id    = 1
  operatingsystem_id = 1
}

# Create a subnet
resource "foreman_subnet" "provisioning" {
  name        = "Provisioning Network"
  network     = "10.50.0.0"
  mask        = "255.255.0.0"
  gateway     = "10.50.0.1"
  dns_primary = "10.5.0.1"
  vlanid      = 50
}

# Create a host
resource "foreman_host" "node01" {
  name         = "ceph-osd-r07-u12"
  hostgroup_id = foreman_hostgroup.ceph_osd.id
  mac          = "00:25:90:e3:6c:4a"
  ip           = "10.50.7.12"
  build        = true
}
```

## What Gets Tested

### Works Great
- Terraform provider initialization
- Resource creation (hostgroups, subnets, hosts)
- Resource updates (PUT)
- Resource deletion (DELETE)
- State management
- Variable interpolation
- Data source queries
- Resource dependencies

### Limitations
- Mock API stores data in memory (lost on restart)
- Simplified responses (not all Foreman fields)
- No actual provisioning
- No template rendering
- No Smart Proxy integration
- No compute resources

## Mock API Logs

```bash
# Watch API requests in real-time
docker logs -f foreman-mock

# You'll see:
# - All API requests
# - Request methods (GET, POST, PUT, DELETE)
# - Response codes
# - Created/updated resources
```

## Troubleshooting

### Terraform Init Fails

```bash
# Error: Failed to query available provider packages
# Solution: Make sure you have internet access for provider download

# Check provider source
cat 00-provider/main.tf | grep source
# Should be: source = "terraform-coop/foreman"
```

### API Not Responding

```bash
# Check container is running
docker ps | grep foreman-mock

# Check logs
docker logs foreman-mock

# Restart if needed
docker restart foreman-mock
```

### Provider Connection Fails

```bash
# Test API manually
curl http://localhost:3000/api/status

# Verify credentials
curl -u admin:changeme123 http://localhost:3000/api/v2/architectures

# Check provider logs
cat terraform-provider-foreman.log
```

### Resources Not Created

```bash
# Check API directly
curl -u admin:changeme123 http://localhost:3000/api/v2/hostgroups | jq .

# Check Terraform state
terraform state list

# Enable debug logging
export TF_LOG=DEBUG
terraform apply
```

## Cleanup

```bash
# Stop environment
cd test-infra
docker-compose -f docker-compose.terraform.yml down

# Remove volumes (clean slate)
docker-compose -f docker-compose.terraform.yml down -v
```

## Next Steps

After testing with mock API:

1. **Refine Terraform code** - Fix any issues found
2. **Install real Foreman** - On bootstrap host (see [FOREMAN_SETUP_GUIDE.md](../FOREMAN_SETUP_GUIDE.md))
3. **Update configuration** - Point to real Foreman
   ```hcl
   provider "foreman" {
     server_hostname = "foreman.example.com"
     server_protocol = "https"
     client_tls_insecure = "false"
   }
   ```
4. **Deploy to hardware** - Use validated Terraform code

## Comparison

| Feature | Mock API | Real Foreman |
|---------|----------|--------------|
| Terraform provider | Yes | Yes |
| Resource creation | Mock (in-memory) | Real (database) |
| API responses | Simplified | Complete |
| OS provisioning | No | Yes |
| PXE boot | No | Yes |
| Templates | No | Yes |
| Smart Proxy | No | Yes |
| Start time | ~10 seconds | ~5 minutes |
| Good for | Development | Production |

---

**Use this for**: Terraform development and testing
**Then use**: Real Foreman on bootstrap host for actual deployment
