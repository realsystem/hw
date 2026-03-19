# Observability, Security, and Scale Architecture

## Part 1: Observability Stack

### Monitoring Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Monitoring Control Plane                     │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Prometheus (HA)                                          │  │
│  │  ┌─────────────┐         ┌─────────────┐                 │  │
│  │  │ Prometheus  │◄───────►│ Prometheus  │                 │  │
│  │  │   Primary   │         │  Replica    │                 │  │
│  │  │             │         │             │                 │  │
│  │  │ Retention:  │         │ Retention:  │                 │  │
│  │  │  30 days    │         │  30 days    │                 │  │
│  │  └─────────────┘         └─────────────┘                 │  │
│  │         │                        │                        │  │
│  │         └────────────┬───────────┘                        │  │
│  │                      ▼                                     │  │
│  │            ┌──────────────────┐                           │  │
│  │            │ Thanos Querier   │  (Global Query Layer)     │  │
│  │            └──────────────────┘                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Grafana (Visualization)                                  │  │
│  │  - Provisioning dashboards                                │  │
│  │  - Node lifecycle tracking                                │  │
│  │  - Hardware health monitoring                             │  │
│  │  - Network performance                                    │  │
│  │  - Ceph cluster metrics (post-deployment)                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Alertmanager (Clustering)                                │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐               │  │
│  │  │  Node 1  │◄─┤  Node 2  │◄─┤  Node 3  │               │  │
│  │  └──────────┘  └──────────┘  └──────────┘               │  │
│  │  - PagerDuty integration                                  │  │
│  │  - Slack notifications                                    │  │
│  │  - Email alerts                                           │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ Scrape targets
                               ▼
    ┌──────────────────────────────────────────────────┐
    │         Provisioning Infrastructure              │
    │                                                   │
    │  ┌─────────────┐  ┌──────────────┐  ┌─────────┐ │
    │  │  Foreman    │  │ Smart Proxies│  │  Nodes  │ │
    │  │  :9090      │  │  :9100       │  │ :9100   │ │
    │  └─────────────┘  └──────────────┘  └─────────┘ │
    └──────────────────────────────────────────────────┘
```

### Prometheus Metrics Collection

**Prometheus Config:**
```yaml
# /etc/prometheus/prometheus.yml
global:
  scrape_interval: 30s
  evaluation_interval: 30s
  external_labels:
    cluster: 'provisioning'
    datacenter: 'dc1'

scrape_configs:
  # Foreman application metrics
  - job_name: 'foreman'
    static_configs:
      - targets: ['foreman1.example.com:9090', 'foreman2.example.com:9090']

  # Smart Proxies
  - job_name: 'smart-proxy'
    static_configs:
      - targets:
          - 'foreman-proxy-r3-5.example.com:9100'
          - 'foreman-proxy-r6-9.example.com:9100'
          - 'foreman-proxy-r10-12.example.com:9100'

  # Provisioning nodes (dynamic discovery via Foreman API)
  - job_name: 'ceph-nodes'
    http_sd_configs:
      - url: 'https://foreman.example.com/api/v2/hosts?search=lifecycle_state=READY_CEPH'
        refresh_interval: 5m
    relabel_configs:
      - source_labels: [__meta_foreman_hostname]
        target_label: instance
      - source_labels: [__meta_foreman_hostgroup]
        target_label: hostgroup

  # IPMI metrics
  - job_name: 'ipmi'
    scrape_interval: 60s
    scrape_timeout: 30s
    static_configs:
      - targets:
          - '10.20.7.12:9290'  # IPMI exporter per node or centralized
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: ipmi-exporter.example.com:9290

  # PostgreSQL (Foreman database)
  - job_name: 'postgres'
    static_configs:
      - targets: ['pg-patroni-1.example.com:9187']
```

### Key Metrics and Alerts

**Provisioning Performance:**
```yaml
# /etc/prometheus/rules/provisioning.yml
groups:
  - name: provisioning
    interval: 30s
    rules:
      - alert: ProvisioningStalled
        expr: |
          sum(foreman_host_status{state="PROVISIONING"}) by (hostgroup)
          and
          changes(foreman_host_status{state="PROVISIONING"}[30m]) == 0
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Provisioning stalled for {{ $labels.hostgroup }}"

      - alert: HighProvisionFailureRate
        expr: |
          sum(rate(foreman_host_failures_total[10m])) > 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High provision failure rate: {{ $value }}/min"

      - alert: DHCPPoolExhaustion
        expr: |
          (dhcp_leases_active / dhcp_pool_size) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "DHCP pool {{ $labels.proxy }} at {{ $value | humanizePercentage }} capacity"
```

**Hardware Health:**
```yaml
  - name: hardware
    rules:
      - alert: NodeTemperatureHigh
        expr: ipmi_temperature_celsius > 75
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High temperature on {{ $labels.instance }}: {{ $value }}°C"

      - alert: DiskSMARTFailure
        expr: ceph_disk_smart_health > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "SMART failure detected: {{ $labels.device }} on {{ $labels.instance }}"

      - alert: NetworkLinkDown
        expr: node_network_up{device=~"eth.*|bond.*"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Network link down: {{ $labels.device }} on {{ $labels.instance }}"
```

### Logging Stack

```
┌────────────────────────────────────────────────────────────┐
│                    Centralized Logging                      │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  Loki (Log Aggregation)                              │ │
│  │  - Retention: 30 days                                │ │
│  │  - Index: labels only (efficient storage)            │ │
│  └──────────────────────────────────────────────────────┘ │
│                          ▲                                  │
│                          │                                  │
│  ┌───────────────────────┴───────────────────────────────┐ │
│  │            Promtail (Log Shippers)                    │ │
│  │  - On each node                                       │ │
│  │  - Scrapes journald, /var/log/*                      │ │
│  │  - Labels: hostname, hostgroup, lifecycle_state      │ │
│  └───────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

**Promtail Config:**
```yaml
# /etc/promtail/config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://loki.example.com:3100/loki/api/v1/push

scrape_configs:
  - job_name: journal
    journal:
      json: false
      max_age: 12h
      path: /var/log/journal
      labels:
        job: systemd-journal
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
      - source_labels: ['__journal__hostname']
        target_label: 'hostname'

  - job_name: syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          __path__: /var/log/syslog
```

### Grafana Dashboards

**Provisioning Funnel Dashboard:**
- NEW  DISCOVERING  PROVISIONED  READY_CEPH (conversion rates)
- Average time per state
- Failure rates by state
- Active provisions

**Hardware Health Dashboard:**
- Temperature heatmap by rack
- Fan speed trends
- Power supply status
- SMART errors timeline

**Network Performance Dashboard:**
- Bandwidth by interface
- Packet drops/errors
- TCP retransmits
- MTU negotiation issues

---

## Part 2: Security Architecture

### Defense in Depth

```
┌─────────────────────────────────────────────────────────────┐
│                    Security Layers                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Layer 1: Network Segmentation                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Provisioning VLAN (50) - Isolated, no internet access  │ │
│  │ Management VLAN (10) - Restricted access               │ │
│  │ IPMI VLAN (20) - Management servers only               │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Layer 2: Authentication & Authorization                    │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Foreman: LDAP/AD integration, RBAC                     │ │
│  │ SSH: Key-based auth only, no passwords                 │ │
│  │ IPMI: Unique credentials per node, rotated quarterly   │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Layer 3: Encryption                                        │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ TLS for all HTTP traffic (Foreman, Prometheus)         │ │
│  │ SSH for all management access                          │ │
│  │ Encrypted secrets (HashiCorp Vault)                    │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Layer 4: Audit & Compliance                                │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ auditd on all nodes                                    │ │
│  │ Foreman audit log (who provisioned what, when)         │ │
│  │ Immutable log shipping to SIEM                         │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Credential Management

**HashiCorp Vault Integration:**

```
┌──────────────────────────────────────────────────────────┐
│               HashiCorp Vault                             │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Secrets Engine: KV v2                           │   │
│  │                                                   │   │
│  │  provisioning/ipmi/<hostname>                    │   │
│  │    - username: admin                             │   │
│  │    - password: <generated>                       │   │
│  │    - rotation_date: 2026-03-18                   │   │
│  │                                                   │   │
│  │  provisioning/ssh/deploy_key                     │   │
│  │    - private_key: <PEM>                          │   │
│  │    - public_key: <PEM>                           │   │
│  │                                                   │   │
│  │  provisioning/foreman/api_token                  │   │
│  │    - token: <JWT>                                │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

**Vault Access Pattern:**
```bash
#!/bin/bash
# Foreman Smart Proxy retrieves IPMI credentials from Vault

IPMI_HOST=$1
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="s.xxxxxxxxxxxx"  # From Vault Agent

# Retrieve credentials
CREDS=$(vault kv get -format=json provisioning/ipmi/$IPMI_HOST)
IPMI_USER=$(echo $CREDS | jq -r '.data.data.username')
IPMI_PASS=$(echo $CREDS | jq -r '.data.data.password')

# Execute IPMI command
ipmitool -I lanplus -H $IPMI_HOST -U $IPMI_USER -P $IPMI_PASS $@
```

### SSH Key Management

**Deployment Key Rotation:**
```bash
#!/bin/bash
# /usr/local/bin/rotate-deploy-key.sh

# Generate new key pair
ssh-keygen -t ed25519 -f /tmp/new_deploy_key -N "" -C "provisioning@$(date +%Y%m%d)"

# Store in Vault
vault kv put provisioning/ssh/deploy_key \
  private_key=@/tmp/new_deploy_key \
  public_key=@/tmp/new_deploy_key.pub

# Update Foreman template to use new key
PUBLIC_KEY=$(cat /tmp/new_deploy_key.pub)
curl -X PUT https://foreman.example.com/api/v2/common_parameters/ssh_public_key \
  -H "Authorization: Bearer $FOREMAN_TOKEN" \
  -d "{\"value\": \"$PUBLIC_KEY\"}"

# Cleanup
shred -u /tmp/new_deploy_key /tmp/new_deploy_key.pub
```

### Preseed Security

**Token-Based Preseed URLs:**
```ruby
# Foreman generates one-time tokens for preseed downloads

# In Foreman provisioning template:
url=http://foreman.example.com/unattended/preseed?token=<%= @host.token %>

# Token properties:
# - Unique per host
# - Single-use (invalidated after download)
# - Expires after 24 hours
# - Bound to specific MAC address
```

**Token Validation:**
```ruby
# Foreman controller
def preseed
  token = params[:token]
  host = Host.find_by_token(token)

  if host.nil?
    render plain: "Invalid token", status: :forbidden
    return
  end

  if host.token_expired?
    render plain: "Token expired", status: :forbidden
    return
  end

  # Invalidate token after use
  host.update_attribute(:token, nil)

  # Serve preseed
  render plain: host.preseed_config
end
```

### Audit Logging

**/etc/audit/rules.d/ceph-provisioning.rules:**
```
# Monitor sensitive file changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /root/.ssh/authorized_keys -p wa -k ssh_key_changes

# Monitor IPMI access
-a always,exit -F arch=b64 -S execve -F exe=/usr/bin/ipmitool -k ipmi_access

# Monitor provisioning scripts
-w /usr/local/bin/ipmi-exec.sh -p x -k ipmi_automation
-w /usr/local/bin/hardware-precheck.sh -p x -k provisioning_checks

# Monitor Ansible execution
-a always,exit -F arch=b64 -S execve -F exe=/usr/bin/ansible-playbook -k ansible_runs
```

---

## Part 3: Scale and Reliability

### Control Plane High Availability

**PostgreSQL (Patroni Cluster):**
```yaml
# /etc/patroni/config.yml
scope: foreman-db
name: pg-node1

restapi:
  listen: 10.10.0.5:8008
  connect_address: 10.10.0.5:8008

etcd3:
  hosts: 10.10.0.2:2379,10.10.0.3:2379,10.10.0.4:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 500
        shared_buffers: 16GB
        effective_cache_size: 48GB

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 10.10.0.5:5432
  data_dir: /var/lib/postgresql/13/main
  pgpass: /var/lib/postgresql/.pgpass
  authentication:
    replication:
      username: replicator
      password: repl_pass
    superuser:
      username: postgres
      password: super_pass
```

**HAProxy for PostgreSQL:**
```
# /etc/haproxy/haproxy.cfg
frontend postgres_frontend
    bind *:5432
    mode tcp
    default_backend postgres_backend

backend postgres_backend
    mode tcp
    option tcp-check
    tcp-check connect
    tcp-check send-binary 00000000  # PG protocol
    tcp-check expect binary 00000000
    server pg1 10.10.0.5:5432 check port 8008 httpchk GET /primary
    server pg2 10.10.0.6:5432 check port 8008 httpchk GET /primary backup
    server pg3 10.10.0.7:5432 check port 8008 httpchk GET /primary backup
```

### Foreman Application Scaling

**Load Balancing:**
```
# HAProxy for Foreman web/API
frontend foreman_https
    bind *:443 ssl crt /etc/ssl/foreman.pem
    mode http
    default_backend foreman_app

backend foreman_app
    mode http
    balance leastconn
    option httpchk GET /api/status
    cookie FOREMANSERVER insert indirect nocache
    server foreman1 10.10.0.8:443 check ssl verify none cookie foreman1
    server foreman2 10.10.0.9:443 check ssl verify none cookie foreman2
```

**Scaling Recommendations:**

| Component | 100 nodes | 500 nodes | 1000 nodes |
|-----------|-----------|-----------|------------|
| Foreman App | 2 instances | 3 instances | 4 instances |
| PostgreSQL | 3-node cluster | 3-node cluster | 5-node cluster |
| Smart Proxies | 3 (per segment) | 6 (per segment) | 12 (per segment) |
| Prometheus | 2 replicas | 2 replicas | 3 replicas |

### Disaster Recovery

**Backup Strategy:**

```bash
#!/bin/bash
# /usr/local/bin/foreman-backup.sh

BACKUP_DIR="/backup/foreman/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# 1. PostgreSQL database
pg_dump -h 10.10.0.10 -U foreman foreman_production | gzip > $BACKUP_DIR/foreman_db.sql.gz

# 2. Foreman configuration
tar -czf $BACKUP_DIR/foreman_config.tar.gz /etc/foreman /etc/foreman-proxy

# 3. SSL certificates
tar -czf $BACKUP_DIR/foreman_certs.tar.gz /etc/puppetlabs/puppet/ssl

# 4. Debian mirror metadata (optional)
rsync -a /var/www/html/debian/dists $BACKUP_DIR/debian_dists/

# Upload to S3/Minio
aws s3 sync $BACKUP_DIR s3://backups/foreman/$(date +%Y%m%d)/

# Retention: 30 days
find /backup/foreman -type d -mtime +30 -exec rm -rf {} \;
```

**Disaster Recovery Runbook:**

1. **Restore PostgreSQL**:
   ```bash
   gunzip < foreman_db.sql.gz | psql -h new-pg-host foreman_production
   ```

2. **Restore Foreman config**:
   ```bash
   tar -xzf foreman_config.tar.gz -C /
   ```

3. **Reconfigure database connection**:
   ```yaml
   # /etc/foreman/database.yml
   production:
     adapter: postgresql
     host: new-pg-host
     database: foreman_production
   ```

4. **Restart services**:
   ```bash
   systemctl restart foreman foreman-proxy
   ```

### Performance Tuning at Scale

**Foreman Settings for 1000+ Nodes:**

```ruby
# config/settings.yaml

:unattended: true
:require_ssl_puppetmasters: true
:restrict_registered_puppetmasters: false
:query_local_nameservers: false
:max_trend: 60
:entries_per_page: 50

# Database connection pooling
:database_pool: 25

# Background job processing (Dynflow)
:dynflow_pool_size: 15

# PXE template cache
:template_cache_ttl: 3600
```

**Smart Proxy Tuning:**
```yaml
# /etc/foreman-proxy/settings.yml
:daemon: true
:https_port: 8443
:trusted_hosts:
  - foreman.example.com
  - foreman2.example.com
:log_level: INFO

# Worker processes
:workers: 8
```

---

## Summary

This comprehensive design provides:

### Observability
- **Metrics**: Prometheus + Thanos (HA, long-term storage)
- **Logs**: Loki + Promtail (centralized, label-based)
- **Visualization**: Grafana dashboards (provisioning funnel, hardware health)
- **Alerting**: Alertmanager (PagerDuty, Slack integration)

### Security
- **Network**: VLAN isolation, firewall rules
- **Authentication**: LDAP/AD, SSH keys, IPMI credential rotation
- **Encryption**: TLS everywhere, Vault for secrets
- **Audit**: auditd, Foreman audit logs, immutable log shipping

### Scale & Reliability
- **HA Control Plane**: PostgreSQL Patroni, Foreman load balancing
- **Horizontal Scaling**: Distributed Smart Proxies
- **Disaster Recovery**: Automated backups, documented runbooks
- **Performance**: Optimized for 1000+ nodes

**Next**: Complete implementation plan with step-by-step deployment guide.
