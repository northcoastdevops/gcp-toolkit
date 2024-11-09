#!/bin/zsh

# Import shared libraries
SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/../lib-common/status-table.zsh"
source "${SCRIPT_DIR}/../lib-common/parallel-processor.zsh"

# Load configuration
CONFIG_FILE="${SCRIPT_DIR}/config/default.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Script-specific configuration
ORG_ID=""
PROJECT_ID=""
LIST_USERS=false
LIST_SERVICE_ACCOUNTS=false
LIST_ALL=false
UNIQUE=false
FIND_EMAIL=""
RESULTS=()
NO_USERS=()
NO_SERVICE_ACCOUNTS=()
TMPDIR="${TMPDIR:-/tmp}"
[[ ! -d "$TMPDIR" ]] && mkdir -p "$TMPDIR"
TMPFILE="$TMPDIR/results.$$"
touch "$TMPFILE" || {
    log "Error: Unable to create temporary file $TMPFILE"
    exit 1
}
CHECK_DEPENDENCIES=false

# Cache configuration - use values from config or defaults
CACHE_DIR="${CACHE_DIR:-${SCRIPT_DIR}/.cache}"
CACHE_TTL="${CACHE_TTL:-3600}"
CACHE_METADATA_FILE="${CACHE_DIR}/metadata.json"
CACHE_COMPRESSION="${CACHE_COMPRESSION:-true}"
NO_CACHE=false

# Add after other imports
source "${SCRIPT_DIR}/lib/cache-prefetch.zsh"
source "${SCRIPT_DIR}/lib/json-processor.zsh"
source "${SCRIPT_DIR}/lib/io-optimizer.zsh"
source "${SCRIPT_DIR}/lib/process-optimizer.zsh"

# Add before main processing
optimize_io
optimize_process

# Modify the main processing loop
main() {
    local projects
    if ! projects=($(gcloud projects list --format="value(projectId)" 2>/dev/null)); then
        log_error "Failed to list projects"
        return 1
    }
    
    if [[ ${#projects[@]} -eq 0 ]]; then
        log_error "No projects found"
        return 1
    }
    
    # Start prefetching project policies
    prefetch_project_policies $projects
    
    # Process in optimized batches
    local current_batch=()
    for project in $projects; do
        current_batch+=($project)
        if ((${#current_batch} >= BATCH_SIZE)); then
            process_batch $current_batch &
            current_batch=()
        fi
    done
    
    # Process remaining projects
    if ((${#current_batch} > 0)); then
        process_batch $current_batch &
    fi
    
    # Wait for all background jobs
    wait
}