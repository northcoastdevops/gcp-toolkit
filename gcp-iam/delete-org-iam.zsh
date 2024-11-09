#!/bin/zsh

# Configuration
BACKUP_DIR="${HOME}/Desktop/gcp-iam-backups"
ORG_ID=""
CONFIRM=false
EMAIL=""
TMPDIR="${TMPDIR:-/tmp}"
TMPFILE="$TMPDIR/delete_results.$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Cleanup
trap '[[ -f "${TMPFILE}" ]] && rm -f "${TMPFILE}"; kill $(jobs -p) 2>/dev/null' EXIT INT TERM

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Input validation
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log "Error: Invalid email format"
        exit 1
    fi
}

# Usage
usage() {
    echo "Usage: $0 --email EMAIL [options]"
    echo ""
    echo "Required:"
    echo "  --email EMAIL               Email address to delete"
    echo "  --confirm                   Required confirmation flag"
    echo ""
    echo "Options:"
    echo "  -o, --organization ORG_ID   Specify organization ID"
    echo "  --backup-dir PATH           Custom backup directory"
    echo "  -h, --help                  Display this help message"
}

# Backup function
backup_user_iam() {
    local email="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local user_dir="${email//[@.]/_}"
    local backup_path="${BACKUP_DIR}/${user_dir}/${timestamp}"
    local restore_script="${backup_path}/restore.sh"
    local summary_file="${backup_path}/summary.txt"
    
    mkdir -p "$backup_path" || {
        log "Error: Unable to create backup directory at $backup_path"
        return 1
    }
    
    # Create restore script
    cat << EOF > "$restore_script"
#!/bin/bash
set -e

# GCP IAM Restore Script
# Generated: $(date)
# User: $email
# Organization: $ORG_ID
# Backup Location: $backup_path

echo "GCP IAM Restore Operation"
echo "========================"
echo "This script will restore IAM bindings for:"
echo "  User: $email"
echo "  Organization: $ORG_ID"
echo "  Backup Date: $(date)"
echo
read -p "Proceed with restore? [y/N] " -r
[[ ! \$REPLY =~ ^[Yy]$ ]] && exit 1

EOF
    
    # Collect and backup current permissions
    log "Collecting current permissions..."
    
    # Organization permissions
    if [[ -n "$ORG_ID" ]]; then
        gcloud organizations get-iam-policy "$ORG_ID" --format=json > "${backup_path}/org_policy.json"
        echo "gcloud organizations set-iam-policy $ORG_ID ${backup_path}/org_policy.json" >> "$restore_script"
    fi
    
    # Project permissions
    local projects=($(gcloud projects list --format="value(projectId)"))
    for project in "${projects[@]}"; do
        local policy_file="${backup_path}/${project}_policy.json"
        if gcloud projects get-iam-policy "$project" --format=json > "$policy_file" 2>/dev/null; then
            echo "gcloud projects set-iam-policy $project ${policy_file}" >> "$restore_script"
            
            # Add to summary
            echo "Project: $project" >> "$summary_file"
            jq -r '.bindings[] | select(.members[] | contains("'"$email"'")) | "  Role: " + .role' "$policy_file" >> "$summary_file"
            echo >> "$summary_file"
        fi
    done
    
    # Make restore script executable
    chmod +x "$restore_script"
    
    # Create summary
    cat << EOF >> "$summary_file"

Restore Instructions:
-------------------
1. Review this summary carefully
2. Ensure you have appropriate permissions
3. Run: ./restore.sh
4. Verify permissions after restore

Backup Location: $backup_path
EOF
    
    log "Backup completed: $backup_path"
    return 0
}

# Delete function
delete_user_iam() {
    local email="$1"
    local projects=($(gcloud projects list --format="value(projectId)"))
    local success=true
    
    log "Starting deletion process for $email"
    
    # Organization level
    if [[ -n "$ORG_ID" ]]; then
        log "Removing from organization $ORG_ID..."
        if ! gcloud organizations remove-iam-policy-binding "$ORG_ID" \
            --member="user:$email" --role="roles/viewer" 2>/dev/null; then
            log "Warning: Failed to remove from organization"
            success=false
        fi
    fi
    
    # Project level
    for project in "${projects[@]}"; do
        log "Processing project: $project"
        local roles=($(gcloud projects get-iam-policy "$project" --format="json" | \
            jq -r '.bindings[] | select(.members[] | contains("'"$email"'")) | .role'))
        
        for role in "${roles[@]}"; do
            if ! gcloud projects remove-iam-policy-binding "$project" \
                --member="user:$email" --role="$role" 2>/dev/null; then
                log "Warning: Failed to remove role $role from project $project"
                success=false
            fi
        done
    done
    
    $success
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --email)
            EMAIL="$2"
            validate_email "$2"
            shift 2
            ;;
        --confirm)
            CONFIRM=true
            shift
            ;;
        -o|--organization)
            ORG_ID="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log "Error: Unknown option $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$EMAIL" ]]; then
    log "Error: --email is required"
    usage
    exit 1
fi

if ! $CONFIRM; then
    log "Error: --confirm is required for safety"
    usage
    exit 1
fi

# Main execution
log "Starting deletion process for: $EMAIL"

# Show warning and confirmation
cat << EOF

${RED}WARNING: This will remove $EMAIL from all projects${RESET}
This operation:
1. Cannot be undone automatically
2. Will remove all IAM bindings
3. May impact user's access to resources
4. Will require manual intervention to restore

EOF

read -p "Are you absolutely sure you want to proceed? [y/N] " -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Operation cancelled"
    exit 1
fi

# Create backup
if ! backup_user_iam "$EMAIL"; then
    log "Error: Backup failed, aborting deletion"
    exit 1
fi

# Perform deletion
echo "Proceeding with deletion..."
if ! delete_user_iam "$EMAIL"; then
    log "Error: Failed to delete user permissions"
    exit 1
fi

echo -e "\n${GREEN}Deletion completed successfully${RESET}"
echo "Backup and restore information:"
echo "  1. Backup location: $BACKUP_DIR"
echo "  2. Review summary.txt for previous permissions"
echo "  3. Run restore.sh to restore permissions"