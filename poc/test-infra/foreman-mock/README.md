# Mock Foreman API Server

Lightweight Flask-based API server that mimics Foreman API responses for testing Terraform provider.

## Purpose

- Test Terraform configurations without full Foreman installation
- Validate resource definitions and dependencies
- Quick development iteration (restarts in seconds)
- No database, no complex dependencies

## What It Does

Responds to Foreman API v2 endpoints:
- `/api/status` - API status
- `/api/v2/architectures` - List architectures
- `/api/v2/operatingsystems` - List operating systems
- `/api/v2/hostgroups` - CRUD operations for hostgroups
- `/api/v2/subnets` - CRUD operations for subnets
- `/api/v2/hosts` - CRUD operations for hosts
- `/api/v2/hosts/:id/power` - Power control (mocked)

## Authentication

HTTP Basic Auth:
- Username: `admin`
- Password: `changeme123`

## Storage

All data stored **in-memory**:
- Lost on container restart
- Good for testing, not for persistence
- Each test run starts fresh

## Running Standalone

```bash
# Build image
docker build -t foreman-mock .

# Run container
docker run -p 3000:3000 foreman-mock

# Test
curl http://localhost:3000/api/status
```

## Running with Docker Compose

```bash
# From test-infra directory
docker-compose -f docker-compose.terraform.yml up -d

# Check logs
docker logs -f foreman-mock
```

## Example Requests

```bash
# Status (no auth)
curl http://localhost:3000/api/status

# List architectures
curl -u admin:changeme123 http://localhost:3000/api/v2/architectures | jq .

# Create hostgroup
curl -X POST http://localhost:3000/api/v2/hostgroups \
  -u admin:changeme123 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Hostgroup",
    "architecture_id": 1,
    "operatingsystem_id": 1
  }' | jq .

# List hostgroups
curl -u admin:changeme123 http://localhost:3000/api/v2/hostgroups | jq .

# Create subnet
curl -X POST http://localhost:3000/api/v2/subnets \
  -u admin:changeme123 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Provisioning",
    "network": "10.50.0.0",
    "mask": "255.255.0.0",
    "gateway": "10.50.0.1"
  }' | jq .
```

## Limitations

- No database (in-memory only)
- Simplified responses (not all Foreman fields)
- No actual provisioning
- No template rendering
- No Smart Proxy integration
- No compute resources
- No validation of dependent resources

## Extending

To add more endpoints, edit `app.py`:

```python
@app.route('/api/v2/new_resource', methods=['GET', 'POST'])
@require_auth
def new_resource():
    if request.method == 'GET':
        return jsonify({"results": []})
    elif request.method == 'POST':
        data = request.json
        # Process and return
        return jsonify(data), 201
```

## Files

- `app.py` - Flask application
- `Dockerfile` - Container image definition
- `README.md` - This file

---

**Purpose**: Testing only
**Not for**: Production use
