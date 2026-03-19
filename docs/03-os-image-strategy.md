# Debian OS Image Strategy

## Overview

Production-grade Debian image management for Ceph infrastructure, ensuring reproducible, versioned, and validated OS deployments across 1000+ nodes.

---

## Debian Version Selection

### Recommended: **Debian 12 (Bookworm)**

**Rationale:**

1. **Ceph Compatibility**
   - Ceph Pacific (16.2.x): Full support
   - Ceph Quincy (17.2.x): Full support
   - Ceph Reef (18.2.x): Full support
   - Ceph Squid (19.2.x): Expected support

2. **Kernel Version**
   - Linux 6.1 LTS (Long Term Support until Dec 2026)
   - Excellent NVMe support
   - Improved blk-mq I/O scheduler
   - Better network stack performance
   - io_uring support (Ceph Quincy+)

3. **Systemd Version**
   - systemd 252 (mature, stable)
   - cgroup v2 support (Ceph prefers v1 still, easy to configure)
   - Improved service isolation

4. **Package Ecosystem**
   - Python 3.11 (Ceph tooling compatibility)
   - Modern GCC 12.2 (performance optimizations)
   - Up-to-date userspace tools

5. **Support Timeline**
   - Security updates: Until June 2026 (3+ years)
   - LTS support: Until June 2028 (5+ years via Extended LTS)
   - Aligns with typical Ceph cluster lifecycle

**Alternative: Debian 11 (Bullseye)**

Consider if:
- Existing infrastructure on Bullseye
- Ceph version requires older dependencies
- Organization policy mandates N-1 release

**Not Recommended: Debian Testing/Sid**
- Unstable for production storage
- Package churn risks breaking Ceph dependencies
- No security support guarantees

---

## Golden Image Pipeline

### Immutable Infrastructure Approach

**Philosophy**: Treat OS images as immutable artifacts, versioned and tested before deployment.

```
┌─────────────────────────────────────────────────────────────────┐
│                   GOLDEN IMAGE BUILD PIPELINE                    │
└─────────────────────────────────────────────────────────────────┘

  ┌──────────────┐
  │ Git Repo     │  Configuration as Code
  │ (preseed,    │  - Preseed templates
  │  scripts)    │  - Package lists
  └──────┬───────┘  - Post-install scripts
         │          - Validation tests
         │
         │ Git push triggers CI
         ▼
  ┌──────────────┐
  │ Jenkins /    │  Build Orchestration
  │ GitLab CI    │  - Runs on schedule (weekly)
  └──────┬───────┘  - Triggered by commits
         │          - Approval gates
         │
         ▼
  ┌──────────────┐
  │ Packer       │  Image Builder
  │ (automated   │  - Provisions VM
  │  install)    │  - Runs preseed install
  └──────┬───────┘  - Executes post-scripts
         │          - Captures filesystem image
         │
         ▼
  ┌──────────────┐
  │ Image        │  Validation
  │ Validation   │  - Boot test
  └──────┬───────┘  - Package verification
         │          - Security scan
         │
         ▼
  ┌──────────────┐
  │ Artifact     │  Storage
  │ Repository   │  - Versioned images
  └──────┬───────┘  - Checksums
         │          - Metadata
         │
         ▼
  ┌──────────────┐
  │ Foreman      │  Deployment
  │ Distribution │  - Sync to Smart Proxies
  └──────────────┘  - Make available for PXE
```

### Build Infrastructure

**Packer Configuration:**

```hcl
# debian-12-ceph.pkr.hcl

source "qemu" "debian-12" {
  iso_url          = "https://cdimage.debian.org/debian-cd/12.5.0/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
  iso_checksum     = "sha256:1234567890abcdef..."
  output_directory = "output-debian-12-ceph"
  shutdown_command = "echo 'packer' | sudo -S shutdown -P now"
  disk_size        = "20G"
  format           = "qcow2"
  accelerator      = "kvm"
  http_directory   = "http"
  ssh_username     = "root"
  ssh_password     = "packer"
  ssh_timeout      = "20m"
  vm_name          = "debian-12-ceph-{{ isotime \"20060102-1504\" }}"
  net_device       = "virtio-net"
  disk_interface   = "virtio"
  boot_wait        = "5s"
  boot_command     = [
    "<esc><wait>",
    "auto preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed-golden.cfg <wait>",
    "debian-installer=en_US.UTF-8 <wait>",
    "locale=en_US.UTF-8 <wait>",
    "kbd-chooser/method=us <wait>",
    "keyboard-configuration/xkb-keymap=us <wait>",
    "netcfg/choose_interface=auto <wait>",
    "netcfg/get_hostname=debian-golden <wait>",
    "netcfg/get_domain=example.com <wait>",
    "<enter><wait>"
  ]
}

build {
  sources = ["source.qemu.debian-12"]

  # Post-install scripts
  provisioner "shell" {
    scripts = [
      "scripts/01-update-system.sh",
      "scripts/02-install-base-packages.sh",
      "scripts/03-kernel-tuning.sh",
      "scripts/04-cleanup.sh"
    ]
  }

  # Validation
  provisioner "shell" {
    script = "scripts/99-validation.sh"
  }

  # Extract kernel and initrd for PXE
  post-processor "shell-local" {
    inline = [
      "mkdir -p artifacts/pxe",
      "virt-ls -a output-debian-12-ceph/debian-12-ceph.qcow2 /boot/ | grep vmlinuz | xargs -I{} virt-copy-out -a output-debian-12-ceph/debian-12-ceph.qcow2 /boot/{} artifacts/pxe/",
      "virt-ls -a output-debian-12-ceph/debian-12-ceph.qcow2 /boot/ | grep initrd | xargs -I{} virt-copy-out -a output-debian-12-ceph/debian-12-ceph.qcow2 /boot/{} artifacts/pxe/"
    ]
  }

  # Generate metadata
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
```

### Golden Image Build Scripts

**01-update-system.sh:**
```bash
#!/bin/bash
set -e

# Update package lists
apt-get update

# Upgrade all packages
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install security updates
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
```

**02-install-base-packages.sh:**
```bash
#!/bin/bash
set -e

# Base system utilities
apt-get install -y \
  vim \
  tmux \
  htop \
  iotop \
  sysstat \
  dstat \
  strace \
  tcpdump \
  net-tools \
  iproute2 \
  iputils-ping \
  ethtool \
  lshw \
  dmidecode \
  smartmontools \
  nvme-cli \
  parted \
  gdisk \
  lvm2 \
  cryptsetup \
  rsync \
  wget \
  curl \
  git \
  jq \
  python3 \
  python3-pip \
  python3-venv

# Monitoring agents
apt-get install -y \
  prometheus-node-exporter

# Time synchronization
apt-get install -y chrony

# Security tools
apt-get install -y \
  openssh-server \
  fail2ban \
  auditd \
  aide

# Performance tuning
apt-get install -y \
  tuned \
  irqbalance

# Kernel headers (for potential drivers)
apt-get install -y linux-headers-$(uname -r)

# Ceph prerequisites (DO NOT install Ceph yet)
apt-get install -y \
  ceph-common \
  python3-ceph-argparse \
  python3-ceph-common

# Remove unnecessary packages
apt-get autoremove -y
apt-get autoclean
```

**03-kernel-tuning.sh:**
```bash
#!/bin/bash
set -e

# Kernel parameters for Ceph (details in Ceph-ready config doc)
cat > /etc/sysctl.d/90-ceph.conf <<'EOF'
# Network tuning
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 300000
net.ipv4.tcp_congestion_control = htcp
net.ipv4.tcp_mtu_probing = 1

# Memory management
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50

# Filesystem
fs.file-max = 2097152
fs.aio-max-nr = 1048576

# Kernel
kernel.pid_max = 4194303
kernel.threads-max = 2097152
EOF

# Apply immediately (for validation)
sysctl -p /etc/sysctl.d/90-ceph.conf

# Disable transparent huge pages (Ceph recommendation)
cat > /etc/systemd/system/disable-thp.service <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages (THP)
After=sysinit.target local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c "echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled"
ExecStart=/bin/sh -c "echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag"

[Install]
WantedBy=multi-user.target
EOF

systemctl enable disable-thp.service

# I/O schedulers will be set per-device at runtime (mq-deadline for SSD, none for NVMe)
```

**04-cleanup.sh:**
```bash
#!/bin/bash
set -e

# Remove build artifacts
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clear logs
find /var/log -type f -exec truncate -s 0 {} \;

# Clear bash history
history -c
rm -f /root/.bash_history

# Remove SSH host keys (regenerated on first boot)
rm -f /etc/ssh/ssh_host_*

# Remove machine-id (regenerated on first boot)
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Ensure SSH host key regeneration on first boot
cat > /etc/rc.local <<'EOF'
#!/bin/bash
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  ssh-keygen -A
fi
exit 0
EOF
chmod +x /etc/rc.local

# Zero out free space (improves compression)
# dd if=/dev/zero of=/EMPTY bs=1M || true
# rm -f /EMPTY

echo "Cleanup complete"
```

**99-validation.sh:**
```bash
#!/bin/bash
set -e

echo "=== Golden Image Validation ==="

# Verify kernel version
KERNEL=$(uname -r)
if [[ ! $KERNEL =~ 6.1 ]]; then
  echo "ERROR: Unexpected kernel version: $KERNEL"
  exit 1
fi
echo " Kernel version: $KERNEL"

# Verify key packages
PACKAGES=(
  "ceph-common"
  "prometheus-node-exporter"
  "chrony"
  "smartmontools"
  "nvme-cli"
)

for pkg in "${PACKAGES[@]}"; do
  if ! dpkg -l | grep -q "^ii  $pkg"; then
    echo "ERROR: Package $pkg not installed"
    exit 1
  fi
done
echo " All required packages installed"

# Verify sysctl settings
SYSCTL_CHECKS=(
  "vm.swappiness=10"
  "net.core.rmem_max=134217728"
)

for check in "${SYSCTL_CHECKS[@]}"; do
  key=$(echo $check | cut -d= -f1)
  expected=$(echo $check | cut -d= -f2)
  actual=$(sysctl -n $key)
  if [ "$actual" != "$expected" ]; then
    echo "ERROR: Sysctl $key = $actual (expected $expected)"
    exit 1
  fi
done
echo " Sysctl parameters configured"

# Verify services enabled
SERVICES=(
  "ssh"
  "chrony"
  "prometheus-node-exporter"
  "disable-thp"
)

for svc in "${SERVICES[@]}"; do
  if ! systemctl is-enabled $svc &>/dev/null; then
    echo "ERROR: Service $svc not enabled"
    exit 1
  fi
done
echo " Required services enabled"

# Verify disk space
ROOT_FREE=$(df / | awk 'NR==2 {print $4}')
if [ $ROOT_FREE -lt 1000000 ]; then
  echo "ERROR: Insufficient free space on /"
  exit 1
fi
echo " Disk space acceptable"

echo "=== Validation PASSED ==="
```

### Image Versioning

**Versioning Scheme:**
```
debian-12.{MINOR}-ceph-{BUILD_DATE}-{GIT_SHA}

Examples:
  debian-12.5-ceph-20260318-a1b2c3d
  debian-12.5-ceph-20260325-e4f5g6h
```

**Metadata File (JSON):**
```json
{
  "image_name": "debian-12.5-ceph-20260318-a1b2c3d",
  "build_date": "2026-03-18T10:30:00Z",
  "debian_version": "12.5",
  "kernel_version": "6.1.0-18-amd64",
  "git_commit": "a1b2c3d4e5f6g7h8i9j0",
  "builder": "jenkins-builder-01",
  "packages": {
    "ceph-common": "17.2.5-1",
    "prometheus-node-exporter": "1.5.0-1",
    "chrony": "4.3-1"
  },
  "checksums": {
    "kernel": "sha256:abc123...",
    "initrd": "sha256:def456...",
    "qcow2": "sha256:ghi789..."
  },
  "validation": {
    "status": "passed",
    "tests_run": 25,
    "tests_passed": 25
  }
}
```

---

## Preseed Template for Bare-Metal

### Foreman Preseed Template

```shell
# Debian 12 Preseed for Ceph Nodes
# Managed by Foreman

#### Localization
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us

#### Network configuration
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string <%= @host.name %>
d-i netcfg/get_domain string <%= @host.domain %>
d-i netcfg/wireless_wep string

# IPv4
d-i netcfg/get_ipaddress string <%= @host.ip %>
d-i netcfg/get_netmask string <%= @host.subnet.mask %>
d-i netcfg/get_gateway string <%= @host.subnet.gateway %>
d-i netcfg/get_nameservers string <%= @host.subnet.dns_primary %> <%= @host.subnet.dns_secondary %>
d-i netcfg/confirm_static boolean true

#### Mirror settings
d-i mirror/country string manual
d-i mirror/http/hostname string <%= @preseed_server %>
d-i mirror/http/directory string <%= @preseed_path %>
d-i mirror/http/proxy string <%= proxy_string %>

#### Account setup
d-i passwd/root-login boolean true
d-i passwd/root-password-crypted password <%= root_pass %>
d-i passwd/make-user boolean false

#### Clock and time zone
d-i clock-setup/utc boolean true
d-i time/zone string UTC
d-i clock-setup/ntp boolean true
d-i clock-setup/ntp-server string <%= @host.params['ntp-server'] || '0.debian.pool.ntp.org' %>

#### Partitioning
# Ceph-specific: OS on /dev/sda, leave other disks untouched

d-i partman-auto/disk string /dev/sda
d-i partman-auto/method string lvm
d-i partman-auto-lvm/guided_size string max
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true

# Custom partition recipe
d-i partman-auto/expert_recipe string                         \
      ceph-os ::                                              \
              1024 1024 1024 ext4                             \
                      $primary{ } $bootable{ }                \
                      method{ format } format{ }              \
                      use_filesystem{ } filesystem{ ext4 }    \
                      mountpoint{ /boot }                     \
              .                                               \
              32768 32768 32768 linux-swap                    \
                      $lvmok{ }                               \
                      method{ swap } format{ }                \
                      lv_name{ swap }                         \
              .                                               \
              102400 102400 102400 ext4                       \
                      $lvmok{ }                               \
                      method{ format } format{ }              \
                      use_filesystem{ } filesystem{ ext4 }    \
                      mountpoint{ / }                         \
                      lv_name{ root }                         \
              .                                               \
              20480 20480 20480 ext4                          \
                      $lvmok{ }                               \
                      method{ format } format{ }              \
                      use_filesystem{ } filesystem{ ext4 }    \
                      mountpoint{ /var }                      \
                      lv_name{ var }                          \
              .                                               \
              10240 10240 10240 ext4                          \
                      $lvmok{ }                               \
                      method{ format } format{ }              \
                      use_filesystem{ } filesystem{ ext4 }    \
                      mountpoint{ /var/log }                  \
                      lv_name{ var_log }                      \
              .                                               \
              10240 10240 -1 ext4                             \
                      $lvmok{ }                               \
                      method{ format } format{ }              \
                      use_filesystem{ } filesystem{ ext4 }    \
                      mountpoint{ /home }                     \
                      lv_name{ home }                         \
              .

d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# Ignore disks other than /dev/sda
d-i partman/early_command string \
    debconf-set partman-auto/disk /dev/sda; \
    for disk in /dev/sd{b..z} /dev/nvme{0..9}n1; do \
        [ -b "$disk" ] && echo "$disk" >> /tmp/ignore_disks; \
    done

#### Package selection
tasksel tasksel/first multiselect standard, ssh-server
d-i pkgsel/include string openssh-server vim chrony prometheus-node-exporter
d-i pkgsel/upgrade select safe-upgrade
popularity-contest popularity-contest/participate boolean false

#### Boot loader installation
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev string /dev/sda

#### Finishing up
d-i finish-install/reboot_in_progress note

#### Post-install commands
d-i preseed/late_command string \
    in-target /bin/bash -c ' \
        # SSH key installation \
        mkdir -p /root/.ssh; \
        echo "<%= @host.params['ssh_public_key'] %>" > /root/.ssh/authorized_keys; \
        chmod 700 /root/.ssh; \
        chmod 600 /root/.ssh/authorized_keys; \
        \
        # Network configuration (static) \
        cat > /etc/network/interfaces <<EOF \
auto lo \
iface lo inet loopback \
\
auto eth0 \
iface eth0 inet static \
    address <%= @host.ip %> \
    netmask <%= @host.subnet.mask %> \
    gateway <%= @host.subnet.gateway %> \
    dns-nameservers <%= @host.subnet.dns_primary %> <%= @host.subnet.dns_secondary %> \
    dns-search <%= @host.domain %> \
EOF \
        \
        # Foreman callback \
        wget -O /dev/null --no-check-certificate <%= foreman_url("built") %>; \
    '
```

### Disk Layout Explanation

**OS Disk (/dev/sda): LVM Layout**

| Partition | Size | Filesystem | Mount | Purpose |
|-----------|------|------------|-------|---------|
| /boot | 1 GB | ext4 | /boot | Boot files, separate from LVM |
| swap | 32 GB | swap | swap | RAM overflow (Ceph prefers minimal swap) |
| root | 100 GB | ext4 | / | OS root filesystem |
| var | 20 GB | ext4 | /var | Variable data, package cache |
| var_log | 10 GB | ext4 | /var/log | Logs (isolated, quota protection) |
| home | 10+ GB | ext4 | /home | User home dirs (remaining space) |

**Total OS Disk**: ~400 GB recommended (SSD preferred)

**Data Disks (/dev/sdb - /dev/sdz): Untouched**

- Left unpartitioned
- Will be claimed by Ceph OSD deployment
- BlueStore will manage these directly

**NVMe Devices**: Also left untouched (used for Ceph journals/WAL/DB)

---

## Alternative: Immutable Root Filesystem

### For Advanced Deployments

**Approach**: Read-only root filesystem, overlayfs for changes

**Benefits:**
- Impossible to drift from golden image
- Fast rollback to known-good state
- Reduced attack surface

**Implementation:**

```bash
# /etc/fstab
/dev/mapper/vg0-root  /  ext4  ro,defaults  0  1

# Overlay for /etc, /var
tmpfs  /overlay  tmpfs  defaults  0  0
overlay  /etc  overlay  lowerdir=/etc,upperdir=/overlay/etc,workdir=/overlay/etc-work  0  0
```

**Trade-offs:**
- More complex troubleshooting
- Configuration management required (Ansible)
- Not standard Debian approach

**Recommendation**: Evaluate after baseline system proven stable.

---

## Package Repository Strategy

### Option 1: Debian Official Mirrors (Simplest)

**Preseed Configuration:**
```
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
```

**Pros:**
- No infrastructure to maintain
- Always up-to-date
- Global CDN

**Cons:**
- External dependency
- Network bandwidth usage (GB per install)
- Cannot pin package versions

### Option 2: Local Debian Mirror (Recommended)

**Tool**: debmirror or apt-mirror

**Setup:**
```bash
# Install
apt-get install debmirror

# Mirror Debian 12
debmirror --method=http \
  --host=deb.debian.org \
  --root=/debian \
  --dist=bookworm,bookworm-updates,bookworm-security \
  --section=main,contrib,non-free-firmware \
  --arch=amd64 \
  --passive \
  --progress \
  /var/www/html/debian

# Daily sync via cron
0 2 * * * /usr/bin/debmirror ... >> /var/log/debmirror.log 2>&1
```

**Storage**: ~150 GB for full Debian 12 mirror

**Preseed Configuration:**
```
d-i mirror/http/hostname string mirror.example.com
d-i mirror/http/directory string /debian
```

### Option 3: Katello/Pulp (Enterprise)

**Full Content Management:**
- Version-controlled package repositories
- Multiple Debian versions
- Synced on-demand or scheduled
- Content views for staged rollouts

**Foreman Integration:**
```
# Create Debian 12 product
hammer product create --name "Debian 12" --organization "MyOrg"

# Add repository
hammer repository create \
  --name "Debian 12 Main" \
  --product "Debian 12" \
  --content-type "deb" \
  --url "http://deb.debian.org/debian" \
  --deb-releases "bookworm" \
  --deb-components "main" \
  --deb-architectures "amd64"

# Sync
hammer repository synchronize --id 1
```

**Recommended for:**
- 500+ nodes
- Strict change control requirements
- Multi-datacenter deployments

---

## Kernel Selection and Tuning

### Kernel Version

**Default**: Debian 12 ships with Linux 6.1 LTS

**Backports** (if needed):
```bash
# Enable backports
echo "deb http://deb.debian.org/debian bookworm-backports main" > /etc/apt/sources.list.d/backports.list

# Install newer kernel
apt-get update
apt-get -t bookworm-backports install linux-image-amd64

# Example: Linux 6.6 from backports (more recent features)
```

**Custom Kernel** (advanced):

Build kernel with Ceph-optimized config:
- Enable io_uring (CONFIG_IO_URING=y)
- RBD block device (CONFIG_BLK_DEV_RBD=m)
- CephFS (CONFIG_CEPH_FS=m)

**Recommendation**: Stick with Debian default 6.1 LTS unless specific feature required.

### Kernel Boot Parameters

**GRUB Configuration:**
```bash
# /etc/default/grub

GRUB_CMDLINE_LINUX="
  net.ifnames=0
  biosdevname=0
  console=tty0
  console=ttyS1,115200n8
  elevator=none
  transparent_hugepage=never
  intel_idle.max_cstate=1
  processor.max_cstate=1
  intel_pstate=disable
  pcie_aspm=off
"

# net.ifnames=0: Predictable interface names (eth0, eth1 instead of ens1f0)
# console=ttyS1: Serial console for SOL capture
# elevator=none: Let blk-mq handle I/O scheduling
# transparent_hugepage=never: Ceph recommendation
# C-state tweaks: Reduce latency (power vs performance trade-off)
# pcie_aspm: Disable power saving for consistent performance
```

**Apply:**
```bash
update-grub
```

---

## Filesystem Selection

### Root Filesystem: ext4

**Rationale:**
- Mature, well-tested
- Excellent performance
- Good tooling (e2fsck, resize2fs)
- Works well with LVM

**Alternative: XFS**
- Better for large files (not relevant for OS partition)
- Slightly faster metadata operations
- Cannot shrink (only grow)

**Not Recommended: btrfs**
- Subvolume complexity
- CoW overhead
- Not Ceph's primary use case

### Ceph OSD Filesystem: BlueStore (No Filesystem)

Ceph's BlueStore manages raw block devices directly:
- No ext4/XFS on data disks
- Better performance
- More control over I/O patterns

---

## Boot Process Optimization

### Fast Boot Settings

**Systemd:**
```ini
# /etc/systemd/system.conf

DefaultTimeoutStartSec=10s
DefaultTimeoutStopSec=10s
```

**Disable Unnecessary Services:**
```bash
systemctl disable bluetooth.service
systemctl disable ModemManager.service
systemctl disable cups.service

# Keep only essential services
systemctl list-unit-files --state=enabled
```

### Serial Console for Remote Management

```bash
# Enable serial console for SOL (Serial-over-LAN)
systemctl enable serial-getty@ttyS1.service

# Configure getty
cat > /etc/systemd/system/serial-getty@ttyS1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --keep-baud 115200,57600,38400,9600 %I $TERM
EOF
```

---

## Image Testing and Validation

### Automated Test Suite

```bash
#!/bin/bash
# test-golden-image.sh

# Deploy test VM from image
virt-install \
  --name test-golden-$(date +%s) \
  --memory 4096 \
  --vcpus 2 \
  --disk path=debian-12-ceph.qcow2,format=qcow2 \
  --import \
  --network network=default \
  --noautoconsole

# Wait for SSH
timeout 300 bash -c 'until nc -z $VM_IP 22; do sleep 5; done'

# Run validation tests
ssh root@$VM_IP '/usr/local/bin/validate-image.sh'

# Verify package versions match manifest
ssh root@$VM_IP 'dpkg -l' > installed-packages.txt
diff installed-packages.txt expected-packages.txt

# Cleanup
virsh destroy test-golden-$TIMESTAMP
virsh undefine test-golden-$TIMESTAMP
```

### Security Scanning

```bash
# Scan for vulnerabilities
trivy fs --severity HIGH,CRITICAL debian-12-ceph.qcow2

# CIS benchmark (Center for Internet Security)
ssh root@$VM_IP '/usr/bin/cis-audit.sh'

# Fail build if critical vulnerabilities found
```

---

## Image Distribution

### Sync to Smart Proxies

```bash
#!/bin/bash
# sync-images.sh

VERSION="debian-12.5-ceph-20260318-a1b2c3d"
PROXIES=(
  "foreman-proxy-r3-5.example.com"
  "foreman-proxy-r6-9.example.com"
  "foreman-proxy-r10-12.example.com"
)

for proxy in "${PROXIES[@]}"; do
  echo "Syncing to $proxy..."

  # Sync kernel
  rsync -avz --progress \
    artifacts/pxe/vmlinuz-* \
    $proxy:/var/lib/tftpboot/boot/debian-12-kernel-$VERSION

  # Sync initrd
  rsync -avz --progress \
    artifacts/pxe/initrd-* \
    $proxy:/var/lib/tftpboot/boot/debian-12-initrd-$VERSION

  # Update Foreman to use new image
  ssh $proxy "
    ln -sf debian-12-kernel-$VERSION /var/lib/tftpboot/boot/debian-12-amd64-linux
    ln -sf debian-12-initrd-$VERSION /var/lib/tftpboot/boot/debian-12-amd64-initrd.gz
  "
done

echo "Image distribution complete: $VERSION"
```

---

## Rollback Strategy

### Blue-Green Deployment

**Maintain two image versions:**
- Blue: Current production version
- Green: New candidate version

**Workflow:**
1. Deploy Green to 10 test nodes
2. Validate for 48 hours
3. If successful, promote Green  Blue
4. Gradually roll out to all nodes

**Foreman Implementation:**

```yaml
# Host group parameters
production_kernel: "debian-12-amd64-linux-v1.2.3"
production_initrd: "debian-12-amd64-initrd-v1.2.3"

candidate_kernel: "debian-12-amd64-linux-v1.2.4"
candidate_initrd: "debian-12-amd64-initrd-v1.2.4"
```

**Quick Rollback:**
```bash
# Symlink swap
ln -sf debian-12-kernel-v1.2.3 /var/lib/tftpboot/boot/debian-12-amd64-linux
ln -sf debian-12-initrd-v1.2.3 /var/lib/tftpboot/boot/debian-12-amd64-initrd.gz

# Any new provisions use old version
```

---

## Summary

This OS image strategy provides:

1. **Reproducibility**: Versioned, tested images
2. **Automation**: Pipeline from code to deployment
3. **Validation**: Comprehensive testing before production
4. **Performance**: Ceph-optimized kernel and disk layout
5. **Scalability**: Efficient distribution to 1000+ nodes
6. **Reliability**: Rollback capability, blue-green deployment
7. **Maintainability**: Clear update process, metadata tracking

**Next**: Supermicro X9 hardware automation and IPMI management.
