#!/bin/bash
# Simulated hardware facts for discovery

cat << FACTS
{
  "hostname": "${HOSTNAME}",
  "node_type": "${NODE_TYPE}",
  "rack": ${NODE_RACK:-0},
  "unit": ${NODE_UNIT:-0},
  "cpu": {
    "count": 20,
    "model": "Intel Xeon E5-2670",
    "cores": 20,
    "threads": 40
  },
  "memory": {
    "total_gb": 256,
    "modules": 16,
    "speed": "1600 MHz"
  },
  "disks": [
    {"device": "/dev/sda", "size_gb": 500, "type": "SSD", "model": "Samsung 850 PRO"},
    {"device": "/dev/sdb", "size_gb": 4000, "type": "HDD", "model": "Seagate ST4000"},
    {"device": "/dev/sdc", "size_gb": 4000, "type": "HDD", "model": "Seagate ST4000"},
    {"device": "/dev/sdd", "size_gb": 4000, "type": "HDD", "model": "Seagate ST4000"},
    {"device": "/dev/sde", "size_gb": 4000, "type": "HDD", "model": "Seagate ST4000"},
    {"device": "/dev/sdf", "size_gb": 4000, "type": "HDD", "model": "Seagate ST4000"},
    {"device": "/dev/sdg", "size_gb": 4000, "type": "HDD", "model": "Seagate ST4000"},
    {"device": "/dev/sdh", "size_gb": 4000, "type": "HDD", "model": "Seagate ST4000"},
    {"device": "/dev/sdi", "size_gb": 4000, "type": "HDD", "model": "Seagate ST4000"},
    {"device": "/dev/sdj", "size_gb": 4000, "type": "HDD", "model": "Seagate ST4000"},
    {"device": "/dev/sdk", "size_gb": 4000, "type": "HDD", "model": "Seagate ST4000"},
    {"device": "/dev/sdl", "size_gb": 4000, "type": "HDD", "model": "Seagate ST4000"}
  ],
  "network": {
    "interfaces": [
      {"name": "eth0", "mac": "52:54:00:aa:bb:01", "speed": "10G"},
      {"name": "eth1", "mac": "52:54:00:aa:bb:11", "speed": "10G"}
    ]
  },
  "ipmi": {
    "address": "${IPMI_ADDRESS}",
    "version": "2.0"
  },
  "management_ip": "${MANAGEMENT_IP}"
}
FACTS
