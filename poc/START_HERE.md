#  START HERE - Read This First!

## Do You Have Foreman Already?

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│   CRITICAL QUESTION: Do you have Foreman deployed?        │
│                                                              │
│     YES ── Go to Section A (Quick Start)                   │
│      NO ── Go to Section B (Deploy Foreman First)          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Section A: You Have Foreman 

**If you answered YES** (you have Foreman running):

### Quick Start (90 minutes)

```bash
# 1. Navigate to POC directory
cd /path/to/poc

# 2. Configure credentials
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
# Add your Foreman URL: https://your-foreman-server.com
# Add your username: admin
# Add your password: ********
# Add your SSH public key: ssh-rsa AAA...

# 3. Test connection
cd terraform/00-provider
terraform init
terraform apply  # Should show "connected"

# 4. Run POC
cd ../..
./quick-start.sh
```

**Next:** Follow [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)

**Timeline:** 90 minutes total

---

## Section B: You DON'T Have Foreman 

**If you answered NO** (starting from scratch):

### Complete Deployment Path (3-4 hours)

```
┌──────────────────────────────────────────────────────────┐
│ STEP 1: Deploy Foreman Infrastructure (2-3 hours)        │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  See: FOREMAN_SETUP_GUIDE.md                              │
│                                                           │
│  Options:                                                 │
│  • All-in-One (quickest): 1-2 hours                       │
│  • Production HA setup: 1-2 weeks                         │
│                                                           │
└──────────────────────────────────────────────────────────┘
                            
┌──────────────────────────────────────────────────────────┐
│ STEP 2: Verify Foreman Works (15 minutes)                │
├──────────────────────────────────────────────────────────┤
│                                                           │
│   Open browser: https://<your-server-ip>               │
│   Login: admin / changeme                              │
│   Configure Debian repository                          │
│   Create subnets                                       │
│   Test PXE boot with 1 server                          │
│                                                           │
│  Full checklist: PREREQUISITES.md                        │
│                                                           │
└──────────────────────────────────────────────────────────┘
                            
┌──────────────────────────────────────────────────────────┐
│ STEP 3: Run Terraform POC (90 minutes)                   │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  cd /path/to/poc                       │
│  cp terraform.tfvars.example terraform.tfvars            │
│  vim terraform.tfvars  # Add Foreman URL from Step 1     │
│  ./quick-start.sh                                        │
│                                                           │
│  Full guide: DEPLOYMENT_GUIDE.md                         │
│                                                           │
└──────────────────────────────────────────────────────────┘
```

**Timeline:** 3-4 hours total (2-3h Foreman + 90min POC)

---

## What This POC Does

**Summary**: Automates bare-metal provisioning using Foreman (already deployed) + Terraform + Ansible.

**Key Point**: This POC requires Foreman to be deployed first. It orchestrates Foreman but does not deploy it.

For detailed workflow, see [README.md](README.md#architecture).

---

## File Guide

### Read in This Order:

| # | File | When | Purpose |
|---|------|------|---------|
| 1️⃣ | **[START_HERE.md](START_HERE.md)** | **Now!** | This file - determines your path |
| 2️⃣ | **[PREREQUISITES.md](PREREQUISITES.md)** | Before starting | Detailed requirements |
| 3️⃣ | **[FOREMAN_SETUP_GUIDE.md](FOREMAN_SETUP_GUIDE.md)** | If no Foreman | How to deploy Foreman |
| 4️⃣ | **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** | During POC | Step-by-step POC execution |
| 5️⃣ | **[README.md](README.md)** | Reference | Overview and troubleshooting |
| 6️⃣ | **[POC_SUMMARY.md](POC_SUMMARY.md)** | After POC | Results and next steps |

---

## Common Questions

**Q: Can I skip Foreman?**
A: No. This POC requires Foreman (PXE boot, hardware discovery, OS installation).

**Q: How long does Foreman take to deploy?**
A: 1-2 hours (all-in-one) or 1-2 weeks (production HA).

**Q: Can I use MAAS instead?**
A: Technically yes, but you'd need to rewrite all Terraform configs.

**Q: Production ready?**
A: The approach scales to 1000+ nodes. See [../docs/07-implementation-plan.md](../docs/07-implementation-plan.md).

---

## Decision Tree

```
┌─────────────────────────────────────────┐
│  Do you have Foreman deployed?          │
└─────┬─────────────────────┬─────────────┘
      │                     │
     YES                   NO
      │                     │
      ▼                     ▼
┌─────────────┐    ┌──────────────────┐
│ Go to       │    │ Deploy Foreman   │
│ Section A   │    │ (1-2 hours)      │
│             │    │                  │
│ Run POC     │    │ See:             │
│ (90 min)    │    │ FOREMAN_SETUP    │
└─────────────┘    │ _GUIDE.md        │
                   └─────────┬────────┘
                             │
                             │ Done?
                             ▼
                   ┌──────────────────┐
                   │ Then go to       │
                   │ Section A        │
                   └──────────────────┘
```

---

## What's Included

 **Automated**: Terraform configs, Ansible playbooks, validation tests, IPMI scripts, documentation
 **Manual Setup Required**: Foreman, PostgreSQL, Smart Proxy, network infrastructure

See [FILES_CREATED.md](FILES_CREATED.md) for complete file listing.

---

## Success Criteria

### You Can Start the POC When:

```bash
# All of these commands succeed:

# 1. Foreman web UI loads
curl -k https://foreman.example.com/api/status
# Returns: {"status":"ok"}

# 2. Authentication works
curl -k -u "admin:password" \
  https://foreman.example.com/api/v2/architectures
# Returns: JSON (not 401 error)

# 3. Smart Proxy is green
# Check in Foreman UI: Infrastructure  Smart Proxies
# Status: All green checkmarks

# 4. Test PXE boot works
# Power on a server, it should:
# - Get DHCP address
# - Download boot files via TFTP
# - Boot discovery image or installer
```

**All green?**  Continue to [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)

**Any red?**  Fix issues, see [FOREMAN_SETUP_GUIDE.md](FOREMAN_SETUP_GUIDE.md) troubleshooting

---

## Time Estimates

| Scenario | Time |
|----------|------|
| Have Foreman | 90 min |
| Deploy Foreman + POC | 3-4 hours |
| Production HA + POC | 2-3 weeks |

---

## Need Help?

### I Don't Have Foreman

 Read: **[FOREMAN_SETUP_GUIDE.md](FOREMAN_SETUP_GUIDE.md)**
 Quick start: Section "All-in-One Installation"
 Time: 1-2 hours

### I Have Foreman, Ready for POC

 Read: **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)**
 Configure: `terraform.tfvars`
 Run: `./quick-start.sh`
 Time: 90 minutes

### I'm Not Sure What I Need

 Read: **[PREREQUISITES.md](PREREQUISITES.md)**
 Check: Verification tests
 Decide: Which path to follow

---

## Bottom Line

**Requires Foreman deployed first.**
Budget: 90 min (have Foreman) or 3-4 hours (deploy Foreman + POC).

**Ready?** Choose your path (Section A or B above) and get started!

---

**Last Updated:** 2026-03-18
**POC Version:** 1.0
**Status:** Production-ready demonstration
