# Architecture Decision: Bare-Metal Provisioning Platform

## Executive Summary

**Recommendation: Option B - Foreman + PXE + Ansible**

For a production Ceph deployment at scale (1000+ nodes), I recommend a **Foreman-based architecture** augmented with custom automation. This combines proven enterprise tooling with the flexibility needed for specialized Ceph workflows.

---

## Option Analysis

### Option A: MAAS (Metal as a Service)

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                      MAAS Region Controller                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  PostgreSQL  │  │   HTTP API   │  │  Web UI/REST API │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└────────────────────────────┬────────────────────────────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
    ┌─────▼─────┐      ┌─────▼─────┐     ┌─────▼─────┐
    │   Rack    │      │   Rack    │     │   Rack    │
    │ Controller│      │ Controller│     │ Controller│
    │  (DHCP,   │      │  (DHCP,   │     │  (DHCP,   │
    │   TFTP)   │      │   TFTP)   │     │   TFTP)   │
    └───────────┘      └───────────┘     └───────────┘
         │                  │                  │
    [Servers]          [Servers]          [Servers]
```

**Strengths:**
- **Native bare-metal focus**: Built specifically for physical infrastructure
- **Hardware discovery**: Excellent automatic detection via BMC/IPMI
- **Network modeling**: VLAN, bond, bridge configuration built-in
- **Commissioning scripts**: Extensible hardware inspection framework
- **Ubuntu ecosystem**: Canonical backing, good community
- **API-first**: Programmatic control of entire lifecycle
- **Cloud-init integration**: Familiar configuration patterns

**Weaknesses:**
- **Ubuntu-centric**: Debian support exists but less mature than Ubuntu
- **PostgreSQL dependency**: Additional operational complexity
- **Region/Rack split**: Complex HA setup for region controller
- **Configuration drift**: Post-deployment config requires external tools (Ansible/Salt)
- **Ceph integration**: No native Ceph deployment (needs ceph-ansible/cephadm)
- **Learning curve**: MAAS-specific concepts and workflows
- **Version compatibility**: Breaking changes between major versions

**Operational Concerns:**
- Region controller SPOF unless HA configured (requires shared PostgreSQL)
- Database backups critical for disaster recovery
- Upgrade path can be disruptive
- Limited offline provisioning capabilities

**Best For:**
- Ubuntu-first environments
- Teams familiar with Canonical ecosystem
- Environments needing extensive VLAN/networking automation
- Public cloud-like bare-metal experience

---

### Option B: Foreman + PXE + Ansible

**Architecture:**
```
┌────────────────────────────────────────────────────────────────┐
│                    Foreman Control Plane (HA)                   │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐  ┌─────────────┐  │
│  │ Foreman  │  │  Smart   │  │ PostgreSQL │  │   Ansible   │  │
│  │   App    │◄─┤  Proxy   │  │  (Patroni) │  │  AWX/Tower  │  │
│  └──────────┘  └──────────┘  └────────────┘  └─────────────┘  │
│       │             │                                           │
│  ┌────▼─────┐  ┌───▼──────┐                                    │
│  │ Katello  │  │ Pulp 3   │  (Optional: content management)    │
│  └──────────┘  └──────────┘                                    │
└────────────────────────────┬───────────────────────────────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
    ┌─────▼─────┐      ┌─────▼─────┐     ┌─────▼─────┐
    │   Smart   │      │   Smart   │     │   Smart   │
    │   Proxy   │      │   Proxy   │     │   Proxy   │
    │  (DHCP,   │      │  (DHCP,   │     │  (DHCP,   │
    │TFTP,DNS,  │      │TFTP,DNS,  │     │TFTP,DNS,  │
    │ Puppet/   │      │ Puppet/   │     │ Puppet/   │
    │ Ansible)  │      │ Ansible)  │     │ Ansible)  │
    └───────────┘      └───────────┘     └───────────┘
         │                  │                  │
    [Servers]          [Servers]          [Servers]
         │                  │                  │
         └──────────────────┴──────────────────┘
                            │
                    ┌───────▼────────┐
                    │  Ansible AWX   │
                    │  (Post-Config) │
                    │                │
                    │  - Playbooks   │
                    │  - Inventories │
                    │  - Workflows   │
                    └────────────────┘
```

**Strengths:**
- **Multi-OS excellence**: First-class Debian, RHEL, Ubuntu, SLES support
- **Mature ecosystem**: 15+ years of production use
- **Separation of concerns**: PXE/DHCP (Foreman)  Config (Ansible)
- **Ansible integration**: Native support for post-deployment automation
- **Smart Proxy architecture**: Distributed, resilient, scales horizontally
- **Template system**: Kickstart/Preseed templates with ERB flexibility
- **Host groups**: Hierarchical configuration inheritance
- **Content management**: Katello/Pulp for package repositories (optional)
- **Compute resource abstraction**: BMC/IPMI as "compute resource"
- **Fact collection**: Rich hardware inventory database
- **Webhooks & integrations**: External monitoring, CMDB sync
- **Community**: Large enterprise user base (Red Hat, CERN, Universities)

**Weaknesses:**
- **Complexity**: Many moving parts (Foreman, Smart Proxy, Puppet/Ansible, PostgreSQL)
- **Resource overhead**: Requires dedicated control plane infrastructure
- **UI performance**: Web interface can be slow with 1000+ hosts
- **Documentation**: Sometimes fragmented across Foreman/Katello/Puppet
- **Initial setup**: Steeper learning curve than simpler solutions

**Operational Strengths:**
- **HA capable**: PostgreSQL Patroni cluster, multiple Foreman instances
- **Smart Proxy resilience**: Per-rack proxies survive control plane outage
- **Ansible separation**: Config management decoupled from provisioning
- **Role-based access**: Multi-team environments
- **Audit logging**: Complete provisioning history
- **API completeness**: Full automation via RESTful API

**Ceph-Specific Advantages:**
- **Multi-network support**: Provision, mgmt, public, cluster networks
- **Disk preservation**: Preseed templates leave data disks untouched
- **Hardware classes**: Different configs for OSD, MON, MGR nodes
- **Ansible integration**: Seamless handoff to ceph-ansible
- **Inventory source**: Foreman as dynamic inventory for Ansible

**Best For:**
- **Multi-distribution environments** (our case: Debian)
- **Large scale** (1000+ nodes)
- **Long-term operations** (5-10 year lifecycle)
- **Heterogeneous hardware** (different server generations)
- **Ceph deployments** (proven at CERN, OVH, other large storage operators)
- **Enterprise requirements** (RBAC, audit, compliance)

---

### Option C: Custom Lightweight Stack

**Architecture:**
```
┌────────────────────────────────────────────────────────┐
│               Control Plane (Custom Build)              │
│  ┌──────────────────┐  ┌──────────────────────────┐   │
│  │  State Database  │  │   API Server (FastAPI/   │   │
│  │  (etcd cluster)  │  │   Go + gRPC)             │   │
│  └──────────────────┘  └──────────────────────────┘   │
│  ┌──────────────────┐  ┌──────────────────────────┐   │
│  │  Image Builder  │  │  IPMI Orchestrator       │   │
│  │  (Packer/        │  │  (Python/Rust workers)   │   │
│  │   Debian Live)   │  │                          │   │
│  └──────────────────┘  └──────────────────────────┘   │
└──────────────────────────┬─────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   ┌────▼─────┐       ┌────▼─────┐      ┌────▼─────┐
   │ Boot Svc │       │ Boot Svc │      │ Boot Svc │
   │ (DHCP+   │       │ (DHCP+   │      │ (DHCP+   │
   │  HTTP)   │       │  HTTP)   │      │  HTTP)   │
   └──────────┘       └──────────┘      └──────────┘
        │                  │                  │
   [Servers]          [Servers]          [Servers]
```

**Components:**
- **State database**: etcd or Consul for node state
- **API server**: gRPC/REST API for orchestration
- **Boot services**: dnsmasq (DHCP) + nginx/httpd (iPXE)
- **Image builder**: Automated Debian image generation
- **IPMI orchestrator**: Power/boot control workers
- **Config injector**: Cloud-init or custom agent

**Strengths:**
- **Simplicity**: Only components you need, nothing extra
- **Performance**: Optimized for your exact use case
- **Flexibility**: Complete control over workflows
- **Low overhead**: Minimal resource consumption
- **Modern stack**: Use current best practices (gRPC, etcd, containers)
- **Debugging**: Full control of code paths
- **Integration**: Easy to integrate with existing tooling

**Weaknesses:**
- **Development cost**: 6-12 months for production-ready system
- **Maintenance burden**: You own all code and bugs
- **Feature creep**: Constantly adding "one more thing"
- **Staffing risk**: Requires dedicated team with specialized knowledge
- **Bus factor**: Knowledge concentrated in few engineers
- **Security**: Must implement authentication, authorization, audit
- **Testing**: Need comprehensive test coverage
- **Documentation**: Must write and maintain all docs
- **On-call**: Your team owns all issues
- **Upgrades**: No upstream security patches
- **Community**: No external community to lean on

**Hidden Costs:**
- UI development (or operate via CLI/API only)
- Monitoring/metrics integration
- Log aggregation
- Backup/restore procedures
- Disaster recovery testing
- Migration tools
- API versioning
- Client libraries
- Operational runbooks

**When to Consider:**
- Existing similar infrastructure (you're already doing this)
- Very specific requirements not met by existing tools
- Team of 5+ infrastructure engineers
- 3+ year investment commitment
- Unique compliance/security requirements

**Reality Check:**
Most organizations **underestimate** the effort required. What starts as "just PXE boot and Ansible" becomes a full platform. Unless you have clear gaps that existing tools cannot fill, this is **not recommended**.

---

### Option D: Cloud-Style Bare-Metal Platform

**Architecture:**
```
┌────────────────────────────────────────────────────────────┐
│                  Tinkerbell Control Plane                   │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  ┌───────────┐  │
│  │  Boots  │  │Hegel     │  │ Tink      │  │ Rufio     │  │
│  │ (DHCP/  │  │(Metadata)│  │ (Workflow)│  │ (BMC)     │  │
│  │  TFTP)  │  └──────────┘  └───────────┘  └───────────┘  │
│  └─────────┘                      │                        │
│  ┌─────────────────────────────┐  │                        │
│  │  PostgreSQL (State)         │◄─┘                        │
│  └─────────────────────────────┘                           │
└────────────────────────────────────────────────────────────┘
         │                                   │
    ┌────▼─────────────────────────┐   ┌────▼──────┐
    │   Worker Nodes Boot via PXE   │   │   Hook    │
    │   Execute Workflows:          │   │ (Initrd   │
    │   1. Hardware discovery       │   │  OS)      │
    │   2. Disk partitioning        │   └───────────┘
    │   3. Image installation       │
    │   4. Configuration            │
    └───────────────────────────────┘
```

**Modern Alternatives:**
- **Tinkerbell** (Equinix Metal's platform, now CNCF)
- **Ironic** (OpenStack bare-metal)
- **Cluster API + Metal³**

**Strengths:**
- **Cloud-native**: Kubernetes-based, GitOps-ready
- **Workflow model**: Declarative provisioning pipelines
- **Modern tooling**: gRPC, containers, declarative config
- **Equinix backing**: Production-proven at scale
- **Immutable infrastructure**: Treat servers like cattle
- **API-driven**: Everything as code

**Weaknesses:**
- **Kubernetes requirement**: Need K8s cluster to provision bare-metal (chicken-egg)
- **Maturity**: Newer than Foreman/MAAS (Tinkerbell ~4 years old)
- **Complexity**: Kubernetes operational overhead
- **Ecosystem**: Smaller community than established tools
- **Documentation**: Still evolving
- **Debian support**: Primarily tested with Ubuntu/Flatcar
- **Debugging**: Harder to troubleshoot workflow failures
- **Opinionated**: Cloud-native patterns may not fit traditional datacenter

**Best For:**
- Kubernetes-first organizations
- Cloud-native operational model
- Teams already running K8s control planes
- Edge computing deployments
- Organizations migrating from cloud to bare-metal

---

## Decision Matrix

| Criterion | MAAS | Foreman | Custom | Cloud-Style |
|-----------|------|---------|--------|-------------|
| **Debian Support** | Good | Excellent | Perfect | Fair |
| **Scale (1000+ nodes)** | Excellent | Excellent | TBD | Good |
| **Ceph Integration** | Via ceph-ansible | Via ceph-ansible | Custom | Via workflow |
| **Multi-Network** | Excellent | Excellent | Custom | Good |
| **HA Control Plane** | Complex | Proven | Custom | K8s-native |
| **Operational Maturity** | Good | Excellent | N/A | Fair |
| **Time to Production** | 4-6 weeks | 6-8 weeks | 6-12 months | 8-12 weeks |
| **Maintenance Burden** | Medium | Medium | High | Medium-High |
| **Team Learning Curve** | Medium | Medium-High | Low (your code) | High |
| **Community Support** | Good | Excellent | None | Growing |
| **Enterprise Adoption** | Medium | High | N/A | Low |
| **Total Cost (3 years)** | Medium | Medium | High | Medium |
| **Bus Factor Risk** | Low | Low | High | Medium |

---

## Recommendation: Foreman + Ansible

### Why Foreman?

1. **Production-Proven for Ceph**
   - CERN LHC Computing Grid uses Foreman + Ceph (10,000+ nodes)
   - OVH uses Foreman for bare-metal provisioning
   - Multiple large storage providers rely on this stack

2. **Debian First-Class Support**
   - Excellent Preseed template support
   - Debian-specific package repositories
   - Long history in Debian community

3. **Scale & Reliability**
   - Proven at 10,000+ node scale
   - HA architecture well-documented
   - Smart Proxy distribution handles network partitions

4. **Ceph Workflow Integration**
   - Foreman provisions bare OS
   - Dynamic inventory export to Ansible
   - ceph-ansible deploys Ceph cluster
   - Foreman facts  monitoring integration
   - Clean separation of concerns

5. **Long-Term Operations**
   - Active development (backed by Red Hat ecosystem)
   - Security updates and CVE response
   - Upgrade paths between versions
   - Large community for troubleshooting

6. **Flexibility Without Reinvention**
   - Extensive template system for customization
   - Plugin architecture for extensions
   - API for custom tooling
   - Don't rebuild what exists

### Architecture Approach

```
┌─────────────────────────────────────────────────────────────┐
│  Phase 1: Provisioning (Foreman + Smart Proxy)              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  1. Hardware discovery via IPMI                      │   │
│  │  2. PXE boot Debian installer                        │   │
│  │  3. Preseed automated installation                   │   │
│  │  4. Base OS configuration                            │   │
│  │  5. Register with Foreman (facts collection)         │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 2: Configuration (Ansible)                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  1. Foreman  Ansible dynamic inventory              │   │
│  │  2. Apply Ceph-ready node configuration              │   │
│  │  3. Network tuning, kernel parameters                │   │
│  │  4. Monitoring agent installation                    │   │
│  │  5. Validation tests                                 │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Phase 3: Ceph Deployment (ceph-ansible / cephadm)          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  1. Inventory from Foreman                           │   │
│  │  2. Deploy Ceph monitors                             │   │
│  │  3. Deploy Ceph OSDs                                 │   │
│  │  4. Deploy Ceph managers, RGW, MDS, etc.             │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Implementation Timeline

**Weeks 1-2: Foundation**
- Deploy Foreman control plane (HA PostgreSQL + 2x Foreman instances)
- Configure Smart Proxies (1 per rack or network segment)
- Set up DHCP, TFTP, DNS infrastructure
- Create base Debian image/mirror

**Weeks 3-4: Provisioning Pipeline**
- Build Supermicro X9 hardware model
- Create Preseed templates for Ceph nodes
- Implement IPMI automation scripts
- Test provisioning workflows

**Weeks 5-6: Ansible Integration**
- Create Ansible roles for Ceph-ready configuration
- Build dynamic inventory integration
- Develop validation playbooks
- Create monitoring integration

**Weeks 7-8: Production Hardening**
- HA testing and failover validation
- Security hardening (TLS, RBAC, audit)
- Backup/restore procedures
- Documentation and runbooks

**Week 9+: Scale Testing**
- Provision 10, 50, 100, 500 node batches
- Performance tuning
- Monitoring dashboards
- Team training

---

## Alternative Consideration: MAAS

If you have **strong Ubuntu preference** or **existing Canonical relationships**, MAAS is a solid alternative:

**Use MAAS if:**
- Team has existing MAAS experience
- Ubuntu is acceptable for Ceph nodes
- You need simpler initial setup
- Network automation is critical (VLANs, bonds, etc.)

**Stick with Foreman if:**
- Debian is required (Ceph team preference, compliance)
- You need proven 1000+ node scale
- Multi-OS environment likely in future
- You want separation between provisioning and configuration
- Enterprise support requirements (Red Hat partnership)

---

## Not Recommended

**Custom Stack**: Only consider if you have:
- Team of 5+ dedicated infrastructure engineers
- 12+ month timeline
- Clear gaps in existing tools
- Long-term commitment (3+ years)

**Cloud-Style (Tinkerbell/Ironic)**: Only if:
- Already operating Kubernetes at scale
- Cloud-native operational model
- Can accept bleeding-edge risk

---

## Success Criteria

Your provisioning platform must achieve:

1. **Reliability**: 99.9% successful provisions
2. **Scale**: 100+ simultaneous provisions without degradation
3. **Speed**: 15-20 minutes bare-metal to ready-for-Ceph
4. **Repeatability**: Identical configuration across all nodes
5. **Observability**: Full visibility into provisioning state
6. **Recovery**: Fast reprovisioning for failed hardware
7. **Security**: Audited, authenticated, encrypted
8. **Maintainability**: Team can operate without specialized knowledge

**Foreman + Ansible meets all criteria with proven production track record.**

---

## Next Steps

1. Review this decision with team
2. Approve Foreman-based architecture
3. Proceed to detailed design phases:
   - Node lifecycle model
   - Network boot infrastructure
   - OS image strategy
   - Hardware automation
   - Ceph-ready configuration
   - Observability stack
   - Security architecture
   - Implementation plan
