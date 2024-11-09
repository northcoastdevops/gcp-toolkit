#!/bin/zsh

# Backup management
MAX_BACKUPS=10
BACKUP_TTL=$((30 * 24 * 60 * 60))  # 30 days in seconds

cleanup_old_backups() {
    local backup_dir=$1
    local current_time=$(date +%s)
    
    # Remove old backups
    find "$backup_dir" -type d -mtime +30 -exec rm -rf {} \;
    
    # Keep only last MAX_BACKUPS
    local count=$(ls -1 "$backup_dir" | wc -l)
    if ((count > MAX_BACKUPS)); then
        ls -1t "$backup_dir" | tail -n $((count - MAX_BACKUPS)) | xargs -I {} rm -rf "$backup_dir/{}"
    fi
}

create_backup_metadata() {
    local backup_path=$1
    local email=$2
    cat << EOF > "${backup_path}/metadata.json"
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "user": "$email",
    "organization": "$ORG_ID",
    "tool_version": "${VERSION:-1.0.0}",
    "hostname": "$(hostname)",
    "operator": "$(whoami)"
}
EOF
} 