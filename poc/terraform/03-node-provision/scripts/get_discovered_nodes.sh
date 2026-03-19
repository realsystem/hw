#!/bin/bash
# Query Foreman for discovered nodes
#
# This script is called by Terraform external data source
# Returns JSON with discovered nodes and their hardware facts

set -e

# Read input from stdin (Terraform passes query variables)
eval "$(jq -r '@sh "FOREMAN_URL=\(.foreman_url) FOREMAN_USER=\(.foreman_username) FOREMAN_PASS=\(.foreman_password)"')"

# Query Foreman API for discovered hosts
RESPONSE=$(curl -s -k \
  -u "${FOREMAN_USER}:${FOREMAN_PASS}" \
  -H "Accept: application/json" \
  "${FOREMAN_URL}/api/v2/discovered_hosts")

# Check if request succeeded
if [ $? -ne 0 ]; then
  echo '{"nodes": "[]"}' >&2
  exit 1
fi

# Extract discovered hosts and format for Terraform
NODES=$(echo "$RESPONSE" | jq -c '[
  .results[] | {
    id: .id,
    name: .name,
    mac: .mac,
    ip: .ip,
    subnet_id: .subnet_id,
    ipmi: {
      address: (.facts.ipmi_ipaddress // ""),
      mac: (.facts.ipmi_mac // "")
    },
    facts: {
      processors: {
        count: (.facts.processorcount // 0 | tonumber),
        model: (.facts.processor0 // "unknown")
      },
      memory: {
        total_gb: ((.facts.memorysize_mb // "0") | tonumber / 1024 | floor)
      },
      disks: {
        count: (.facts.blockdevice_count // 0 | tonumber),
        devices: (.facts.blockdevices // "" | split(","))
      },
      network: {
        interfaces: (.facts.interfaces // "" | split(","))
      }
    },
    rack_number: ((.name | capture("r(?<rack>[0-9]+)").rack) // 99 | tonumber),
    unit_number: ((.name | capture("u(?<unit>[0-9]+)").unit) // 99 | tonumber)
  }
]')

# Return JSON (Terraform expects format: {"key": "value"})
jq -n --arg nodes "$NODES" '{"nodes": $nodes}'
