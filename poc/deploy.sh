#!/bin/bash
# Main deployment script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed"
        exit 1
    fi
    
    # Check Ansible
    if ! command -v ansible &> /dev/null; then
        log_error "Ansible is not installed"
        exit 1
    fi
    
    # Check ipmitool
    if ! command -v ipmitool &> /dev/null; then
        log_warn "ipmitool is not installed - IPMI operations may fail"
    fi
    
    # Check terraform.tfvars exists
    if [ ! -f terraform.tfvars ]; then
        log_error "terraform.tfvars not found"
        log_info "Copy terraform.tfvars.example and configure it"
        exit 1
    fi
    
    # Check inventory.yml exists
    if [ ! -f inventory.yml ]; then
        log_error "inventory.yml not found"
        exit 1
    fi
    
    log_info "✓ Prerequisites check passed"
}

deploy_foreman_config() {
    log_info "===== Phase 1: Deploying Foreman Configuration ====="
    cd terraform/01-foreman-config
    
    terraform init
    terraform plan -var-file=../../terraform.tfvars
    
    echo ""
    read -p "Apply Foreman configuration? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_warn "Deployment cancelled"
        exit 0
    fi
    
    terraform apply -var-file=../../terraform.tfvars -auto-approve
    
    cd ../..
    log_info "✓ Foreman configuration complete"
}

provision_nodes() {
    log_info "===== Phase 2: Provisioning Nodes ====="
    cd terraform/02-node-provision
    
    terraform init
    terraform plan -var-file=../../terraform.tfvars
    
    echo ""
    log_warn "This will power on servers and trigger OS installation"
    read -p "Proceed with node provisioning? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_warn "Deployment cancelled"
        exit 0
    fi
    
    terraform apply -var-file=../../terraform.tfvars -auto-approve
    
    cd ../..
    log_info "✓ Node provisioning complete"
}

configure_nodes() {
    log_info "===== Phase 3: Configuring Nodes with Ansible ====="
    
    if [ ! -f ansible/inventory/hosts.yml ]; then
        log_error "Ansible inventory not found"
        log_error "Run node provisioning first"
        exit 1
    fi
    
    cd ansible
    
    # Run baseline configuration
    ansible-playbook -i inventory/hosts.yml playbooks/ceph_baseline.yml
    
    log_info "✓ Node configuration complete"
    
    cd ..
}

validate_deployment() {
    log_info "===== Phase 4: Validating Configuration ====="
    
    cd ansible
    
    ansible-playbook -i inventory/hosts.yml playbooks/validate.yml
    
    cd ..
    
    log_info "✓ Validation complete"
}

display_summary() {
    log_info "===== Deployment Summary ====="
    
    cd terraform/02-node-provision
    terraform output -json > /tmp/tf_output.json
    
    echo ""
    echo "Provisioned Nodes:"
    echo "=================="
    jq -r '.provisioned_nodes.value | to_entries[] | "\(.key): \(.value | to_entries | map("\(.key)=\(.value)") | join(", "))"' /tmp/tf_output.json
    
    echo ""
    echo "Ansible Inventory:"
    echo "=================="
    jq -r '.ansible_inventory_path.value' /tmp/tf_output.json
    
    cd ../..
    
    echo ""
    log_info "===== Deployment Complete! ====="
    log_info "Next steps:"
    echo "  1. Review validation results above"
    echo "  2. Deploy Ceph using ceph-ansible"
    echo "  3. Verify Ceph cluster health"
}

# Main execution
main() {
    log_info "Starting Bare-Metal Provisioning Deployment"
    log_info "============================================"
    echo ""
    
    check_prerequisites
    echo ""
    
    # Phase 1: Foreman configuration
    deploy_foreman_config
    echo ""
    
    # Phase 2: Node provisioning
    provision_nodes
    echo ""
    
    # Phase 3: Ansible configuration
    configure_nodes
    echo ""
    
    # Phase 4: Validation
    validate_deployment
    echo ""
    
    # Summary
    display_summary
}

# Handle script arguments
case "${1:-}" in
    check)
        check_prerequisites
        ;;
    foreman)
        check_prerequisites
        deploy_foreman_config
        ;;
    provision)
        check_prerequisites
        provision_nodes
        ;;
    configure)
        check_prerequisites
        configure_nodes
        ;;
    validate)
        check_prerequisites
        validate_deployment
        ;;
    clean)
        log_warn "Destroying all resources..."
        cd terraform/02-node-provision && terraform destroy -var-file=../../terraform.tfvars -auto-approve
        cd ../01-foreman-config && terraform destroy -var-file=../../terraform.tfvars -auto-approve
        log_info "✓ Cleanup complete"
        ;;
    *)
        main
        ;;
esac
