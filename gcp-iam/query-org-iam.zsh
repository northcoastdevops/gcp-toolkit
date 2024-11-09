#!/bin/zsh

# Import shared libraries
SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/../lib/status-table.zsh"
source "${SCRIPT_DIR}/../lib/parallel-processor.zsh"

# Script-specific configuration
ORG_ID=""
PROJECT_ID=""
LIST_USERS=false
LIST_SERVICE_ACCOUNTS=false
LIST_ALL=false
UNIQUE=false
DEBUG=false
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

# Cache configuration
CACHE_DIR="${HOME}/.cache/gcloud-utils"
CACHE_TTL=3600  # 1 hour
CACHE_METADATA_FILE="${CACHE_DIR}/metadata.json"
CACHE_COMPRESSION=true
NO_CACHE=false
REFRESH_CACHE=false

# Cleanup and signal handling
trap '[[ -f "${TMPFILE}" ]] && rm -f "${TMPFILE}"; kill $(jobs -p) 2>/dev/null' EXIT INT TERM

# Logging function
log() {
    update_operation_status "$*"
}

# Input validation function
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log "Error: Invalid email format"
        exit 1
    fi
}

# Cache management functions
init_cache() {
    [[ ! -d "$CACHE_DIR" ]] && mkdir -p "$CACHE_DIR"/{iam,org,projects}
    [[ ! -f "$CACHE_METADATA_FILE" ]] && echo '{"stats":{"hits":0,"misses":0,"errors":0},"access_counts":{}}' > "$CACHE_METADATA_FILE"
    cleanup_stale_locks
}

acquire_cache_lock() {
    local lock_file="${CACHE_DIR}/.lock_$1"
    local max_wait=30
    local wait_time=0
    
    while ! mkdir "$lock_file" 2>/dev/null; do
        sleep 0.1
        ((wait_time += 1))
        if ((wait_time > max_wait * 10)); then
            return 1
        fi
    done
    return 0
}

release_cache_lock() {
    local lock_file="${CACHE_DIR}/.lock_$1"
    rmdir "$lock_file" 2>/dev/null
}

update_cache_metadata() {
    local cache_type=$1
    local id=$2
    local result=$3
    
    if ! acquire_cache_lock "metadata"; then
        return 1
    fi
    
    local tmp_file="${CACHE_METADATA_FILE}.tmp"
    jq --arg type "$cache_type" \
       --arg id "$id" \
       --arg result "$result" \
       '.stats[$result] += 1 | .access_counts[$type + "_" + $id] += 1' \
       "$CACHE_METADATA_FILE" > "$tmp_file" && \
    mv "$tmp_file" "$CACHE_METADATA_FILE"
    
    release_cache_lock "metadata"
}

cache_is_valid() {
    local file=$1
    local age=$(( $(date +%s) - $(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file") ))
    ((age <= CACHE_TTL))
}

compress_cache_data() {
    gzip -c
}

decompress_cache_data() {
    local file=$1
    if [[ "$file" == *.gz ]]; then
        gzip -dc "$file"
    else
        cat "$file"
    fi
}

get_cached_data() {
    local cache_type="$1"
    local id="$2"
    local cache_file="$CACHE_DIR/${cache_type}/${id}.json"
    local compressed_file="${cache_file}.gz"
    
    if $NO_CACHE; then
        return 1
    fi
    
    if $REFRESH_CACHE; then
        update_cache_metadata "$cache_type" "$id" "miss"
        return 1
    fi
    
    # Check for both compressed and uncompressed files
    local actual_file="$cache_file"
    if [[ -f "$compressed_file" ]]; then
        actual_file="$compressed_file"
    elif [[ ! -f "$cache_file" ]]; then
        update_cache_metadata "$cache_type" "$id" "miss"
        return 1
    fi
    
    if ! cache_is_valid "$actual_file"; then
        update_cache_metadata "$cache_type" "$id" "miss"
        return 1
    fi
    
    if ! acquire_cache_lock "${cache_type}_${id}"; then
        update_cache_metadata "$cache_type" "$id" "error"
        return 1
    fi
    
    decompress_cache_data "$actual_file"
    local status=$?
    
    release_cache_lock "${cache_type}_${id}"
    
    if ((status == 0)); then
        update_cache_metadata "$cache_type" "$id" "hit"
        return 0
    else
        update_cache_metadata "$cache_type" "$id" "error"
        return 1
    fi
}

save_to_cache() {
    local cache_type="$1"
    local id="$2"
    local cache_file="$CACHE_DIR/${cache_type}/${id}.json"
    
    if $NO_CACHE; then
        return 0
    fi
    
    if ! acquire_cache_lock "${cache_type}_${id}"; then
        log "Error: Failed to acquire cache lock for ${cache_type}/${id}"
        return 1
    fi
    
    if $CACHE_COMPRESSION; then
        if ! compress_cache_data > "${cache_file}.gz"; then
            log "Error: Failed to compress cache data for ${cache_type}/${id}"
            release_cache_lock "${cache_type}_${id}"
            return 1
        fi
    else
        if ! cat > "$cache_file"; then
            log "Error: Failed to save cache data for ${cache_type}/${id}"
            release_cache_lock "${cache_type}_${id}"
            return 1
        fi
    fi
    
    release_cache_lock "${cache_type}_${id}"
    return 0
}

# Data fetching functions
fetch_iam_data() {
    local type=$1
    local project=$2
    local scope=$3
    local result=""
    local cache_id="${project}"
    
    # Try to get from cache first
    if result=$(get_cached_data "iam" "${scope}_${cache_id}"); then
        log "Using cached IAM data for $scope $project"
    else
        log "Fetching IAM data for $scope $project..."
        if ! result=$(retry_command "gcloud $scope get-iam-policy '$project' --format='json'"); then
            log "Failed to fetch IAM data after $MAX_RETRIES attempts"
            return 1
        fi
        
        if [[ -n "$result" ]]; then
            echo "$result" | save_to_cache "iam" "${scope}_${cache_id}"
        fi
    fi
    
    if [[ -n "$result" ]]; then
        echo "$result" | jq -r '
            .bindings[] |
            select(.members != null) |
            .role as $role |
            .members[] |
            select(
                startswith("user:") or
                startswith("group:") or
                startswith("deleted:")
            ) |
            [
                "'$project'",
                sub("^(user:|group:|deleted:)"; ""),
                if startswith("group:") then "Group"
                elif startswith("deleted:") then "Deleted"
                else "User"
                end,
                $role
            ] | join("\t")' >> "$TMPFILE"
    fi
}

get_projects() {
    local result=""
    
    if result=$(get_cached_data "projects" "list"); then
        log "Using cached project list"
    else
        log "Fetching project list..."
        result=$(gcloud projects list --format="json" 2>/dev/null)
        
        if [[ -n "$result" ]]; then
            echo "$result" | save_to_cache "projects" "list"
        fi
    fi
    
    if [[ -n "$result" ]]; then
        echo "$result" | jq -r '.[].projectId'
    fi
}

# Process command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--organization)
            ORG_ID="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        --filter)
            FILTER_TYPE="$2"
            shift 2
            ;;
        --check-dependencies)
            CHECK_DEPENDENCIES=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --refresh-cache)
            REFRESH_CACHE=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
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

# Initialize cache
init_cache

# Get list of projects to process
if [[ -n "$PROJECT_ID" ]]; then
    PROJECTS=("$PROJECT_ID")
else
    log "Fetching project list..."
    if ! PROJECTS=($(get_projects)); then
        log "No projects found or insufficient permissions to list projects."
        exit 1
    fi
fi

# Handle cache refresh if requested
if $REFRESH_CACHE; then
    log "Starting cache refresh..."
    
    init_parallel_processor "Refreshing cache (max $MAX_PARALLEL_JOBS concurrent)..."
    
    # Refresh project list
    add_parallel_job "projects:list" \
        "gcloud projects list --format='json' | save_to_cache 'projects' 'list'"
    
    # Refresh IAM policies for all projects
    for PROJECT in "${PROJECTS[@]}"; do
        add_parallel_job "iam:$PROJECT" \
            "gcloud projects get-iam-policy '$PROJECT' --format='json' | save_to_cache 'iam' 'project_$PROJECT'"
    done
    
    # Refresh organization data if available
    if [[ -n "$ORG_ID" ]]; then
        add_parallel_job "org:$ORG_ID" \
            "gcloud organizations get-iam-policy '$ORG_ID' --format='json' | save_to_cache 'org' '$ORG_ID'"
    fi
    
    wait_for_jobs
    log "Cache refresh completed"
fi

# Process projects in parallel
log "Processing projects..."
init_parallel_processor "Processing projects (max $MAX_PARALLEL_JOBS concurrent)..."

for PROJECT in "${PROJECTS[@]}"; do
    case "$FILTER_TYPE" in
        "user")
            add_parallel_job "user:$PROJECT" fetch_iam_data "user" "$PROJECT" "projects"
            ;;
        "service-account")
            add_parallel_job "sa:$PROJECT" fetch_iam_data "serviceAccount" "$PROJECT" "projects"
            ;;
        *)
            add_parallel_job "all:$PROJECT" fetch_iam_data "all" "$PROJECT" "projects"
            ;;
    esac
done

wait_for_jobs
log "Processing completed"

# Process and display results
if [[ -s "$TMPFILE" ]]; then
    sort -u "$TMPFILE"
else
    log "No results found"
fi

# Add after argument parsing
if $CHECK_DEPENDENCIES; then
    check_dependencies
fi

# Add debug logging
if $DEBUG; then
    set -x
    log() {
        update_operation_status "DEBUG: $*"
        echo "DEBUG: $*" >&2
    }
fi

# Add at top with configuration
typeset -g MAX_RETRIES=3
typeset -g RETRY_DELAY=5

# Add new function
retry_command() {
    local cmd="$1"
    local attempt=1
    local result
    
    while ((attempt <= MAX_RETRIES)); do
        if result=$(eval "$cmd" 2>&1); then
            echo "$result"
            return 0
        fi
        
        log "Attempt $attempt failed, retrying in ${RETRY_DELAY}s..."
        sleep $RETRY_DELAY
        ((attempt++))
    done
    
    return 1
}

# Add new function
cleanup_stale_locks() {
    local lock_dir="${CACHE_DIR}"
    local max_age=3600  # 1 hour
    
    find "$lock_dir" -name '.lock_*' -type d -mmin +$((max_age/60)) -exec rmdir {} \; 2>/dev/null
}