#!/bin/bash
# Quick Start Script for Terraform + Foreman + Ansible POC
#
# This automates the complete POC workflow

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================================
# Functions
# ============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prereqs() {
    log_info "Checking prerequisites..."

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found. Install from https://www.terraform.io/downloads"
        exit 1
    fi
    log_info "✓ Terraform $(terraform version -json | jq -r '.terraform_version')"

    # Check Ansible
    if ! command -v ansible &> /dev/null; then
        log_error "Ansible not found. Install with: sudo apt-get install ansible"
        exit 1
    fi
    log_info "✓ Ansible $(ansible --version | head -1 | awk '{print $2}')"

    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Install with: sudo apt-get install jq"
        exit 1
    fi
    log_info "✓ jq installed"

    # Check terraform.tfvars exists
    if [ ! -f "$SCRIPT_DIR/terraform.tfvars" ]; then
        log_error "terraform.tfvars not found!"
        log_info "Copy terraform.tfvars.example to terraform.tfvars and update with your values"
        exit 1
    fi
    log_info "✓ terraform.tfvars found"
}

phase_1_foreman_config() {
    log_info "=========================================="
    log_info "Phase 1: Configuring Foreman"
    log_info "=========================================="

    cd "$SCRIPT_DIR/terraform/01-foreman-config"

    # Copy variables from root
    ln -sf ../../terraform.tfvars terraform.tfvars

    log_info "Initializing Terraform..."
    terraform init

    log_info "Planning Foreman configuration..."
    terraform plan -out=tfplan

    log_info "Applying Foreman configuration..."
    terraform apply tfplan

    log_info "✓ Phase 1 complete"
    log_info ""
}

phase_2_discover_nodes() {
    log_info "=========================================="
    log_info "Phase 2: Discovering Hardware"
    log_info "=========================================="

    log_info "Power on target servers via IPMI..."
    log_warn "Manual step required:"
    log_warn "  1. Power on servers (they will PXE boot)"
    log_warn "  2. Wait 5-10 minutes for discovery"
    log_warn "  3. Verify discovery in Foreman UI"
    log_warn ""

    read -p "Press Enter when nodes are discovered (check Foreman UI)..."

    log_info "✓ Phase 2 complete"
    log_info ""
}

phase_3_provision_nodes() {
    log_info "=========================================="
    log_info "Phase 3: Provisioning Nodes"
    log_info "=========================================="

    cd "$SCRIPT_DIR/terraform/03-node-provision"

    ln -sf ../../terraform.tfvars terraform.tfvars

    log_info "Initializing Terraform..."
    terraform init

    log_info "Planning node provisioning..."
    terraform plan -out=tfplan

    log_info "Applying node provisioning..."
    log_warn "This will trigger OS installation (15-20 min per node)"
    terraform apply tfplan

    log_info "✓ Phase 3 complete"
    log_info ""
}

phase_4_configure_nodes() {
    log_info "=========================================="
    log_info "Phase 4: Post-Configuration (Ansible)"
    log_info "=========================================="

    cd "$SCRIPT_DIR/terraform/04-post-config"

    ln -sf ../../terraform.tfvars terraform.tfvars

    log_info "Initializing Terraform..."
    terraform init

    log_info "Planning post-configuration..."
    terraform plan -out=tfplan

    log_info "Applying Ansible configuration..."
    terraform apply tfplan

    log_info "✓ Phase 4 complete"
    log_info ""
}

display_results() {
    log_info "=========================================="
    log_info "POC Deployment Complete!"
    log_info "=========================================="

    cd "$SCRIPT_DIR/terraform/04-post-config"

    log_info ""
    log_info "Validation Summary:"
    terraform output -json validation_summary | jq -r '
        "  Total tests: \(.total_tests)",
        "  Passed: \(.passed)",
        "  Failed: \(.failed)",
        "  Warnings: \(.warnings)",
        "  Success rate: \(.success_rate)%"
    '

    log_info ""
    log_info "Provisioned Nodes:"
    terraform output -json | jq -r '
        .configuration_status.value |
        "  Nodes configured: \(.nodes_configured)"
    '

    log_info ""
    log_info "Next Steps:"
    terraform output -raw next_steps

    log_info ""
    log_info "Inventory files:"
    log_info "  Ansible: $(terraform output -raw ansible_inventory_path 2>/dev/null || echo 'N/A')"
    log_info "  Ceph: $(terraform output -raw ceph_inventory_path 2>/dev/null || echo 'N/A')"
}

cleanup_confirmation() {
    log_warn ""
    log_warn "=========================================="
    log_warn "CLEANUP MODE"
    log_warn "=========================================="
    log_warn "This will DESTROY all Terraform-managed resources!"
    log_warn ""
    read -p "Are you sure? Type 'yes' to confirm: " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Cleanup cancelled"
        exit 0
    fi

    log_info "Destroying resources..."

    # Destroy in reverse order
    cd "$SCRIPT_DIR/terraform/04-post-config" && terraform destroy -auto-approve || true
    cd "$SCRIPT_DIR/terraform/03-node-provision" && terraform destroy -auto-approve || true
    cd "$SCRIPT_DIR/terraform/01-foreman-config" && terraform destroy -auto-approve || true

    log_info "✓ Cleanup complete"
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Terraform + Foreman + Ansible POC                       ║"
    echo "║  Quick Start Automation Script                           ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    # Parse arguments
    case "${1:-}" in
        cleanup|destroy)
            cleanup_confirmation
            exit 0
            ;;
        status)
            cd "$SCRIPT_DIR/terraform/04-post-config"
            display_results
            exit 0
            ;;
        "")
            # Full deployment
            ;;
        *)
            echo "Usage: $0 [cleanup|status]"
            echo ""
            echo "  (no args)  - Run full POC deployment"
            echo "  cleanup    - Destroy all resources"
            echo "  status     - Display current status"
            exit 1
            ;;
    esac

    # Run full deployment
    check_prereqs
    phase_1_foreman_config
    phase_2_discover_nodes
    phase_3_provision_nodes
    phase_4_configure_nodes
    display_results

    log_info ""
    log_info "🎉 POC deployment successful!"
}

main "$@"
