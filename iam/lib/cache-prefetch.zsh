#!/bin/zsh

# GCP Toolkit by NorthCoast DevOps
# https://www.northcoastdevops.com
# High-performance cache prefetching system

# Initialize branding
TOOLKIT_VERSION="1.0.0"
TOOLKIT_BANNER="GCP Toolkit Cache Prefetch v${TOOLKIT_VERSION}"
TOOLKIT_AUTHOR="NorthCoast DevOps"
TOOLKIT_URL="https://www.northcoastdevops.com"

# Async prefetching configuration
typeset -gA PREFETCH_PIDS
typeset -g PREFETCH_BATCH_SIZE=20

prefetch_project_policies() {
    local projects=($@)
    local batch=()
    local batch_count=0
    
    for project in $projects; do
        batch+=($project)
        ((batch_count++))
        
        if ((batch_count >= PREFETCH_BATCH_SIZE)); then
            _fetch_batch_policies $batch &
            PREFETCH_PIDS[$!]=$batch
            batch=()
            batch_count=0
        fi
    done
    
    # Handle remaining projects
    if ((${#batch} > 0)); then
        _fetch_batch_policies $batch &
        PREFETCH_PIDS[$!]=$batch
    fi
}

_fetch_batch_policies() {
    local projects=($@)
    for project in $projects; do
        if ! check_cache "iam" "projects_${project}"; then
            gcloud projects get-iam-policy "$project" --format=json | 
                compress_cache_data > "${CACHE_DIR}/iam/projects_${project}.gz"
        fi
    done
} 