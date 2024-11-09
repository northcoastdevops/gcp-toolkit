#!/bin/zsh

# Connection pooling
typeset -gA GCLOUD_CONNECTIONS
typeset -g MAX_CONNECTIONS=5
typeset -g CONNECTION_TIMEOUT=300

init_connection_pool() {
    # Validate configuration
    if ((MAX_CONNECTIONS < 1)); then
        log_error "Invalid MAX_CONNECTIONS value: $MAX_CONNECTIONS"
        return 1
    }
    
    # Clear existing connections
    GCLOUD_CONNECTIONS=()
    
    # Initialize pool
    local success=0
    for ((i=1; i<=MAX_CONNECTIONS; i++)); do
        if gcloud auth print-access-token &>/dev/null; then
            GCLOUD_CONNECTIONS[$i]="available"
            ((success++))
        else
            log_error "Failed to initialize connection $i"
        fi
    done
    
    # Ensure minimum viable pool
    if ((success < 1)); then
        log_error "Failed to initialize any connections"
        return 1
    }
    
    return 0
}

get_connection() {
    local start_time=$SECONDS
    local attempts=0
    local max_attempts=5
    
    # Validate pool exists
    if [[ ${#GCLOUD_CONNECTIONS[@]} -eq 0 ]]; then
        log_error "Connection pool not initialized"
        return 1
    }
    
    while ((SECONDS - start_time < CONNECTION_TIMEOUT)); do
        for id in ${(k)GCLOUD_CONNECTIONS}; do
            if [[ ${GCLOUD_CONNECTIONS[$id]} == "available" ]]; then
                # Verify connection is still valid
                if gcloud auth print-access-token &>/dev/null; then
                    GCLOUD_CONNECTIONS[$id]="in_use"
                    echo $id
                    return 0
                else
                    log_error "Connection $id is stale, refreshing"
                    ((attempts++))
                    if ((attempts >= max_attempts)); then
                        log_error "Failed to refresh connection after $max_attempts attempts"
                        return 1
                    fi
                    continue
                fi
            fi
        done
        sleep 0.1
    done
    
    log_error "Connection timeout after ${CONNECTION_TIMEOUT}s"
    return 1
}

release_connection() {
    local id=$1
    GCLOUD_CONNECTIONS[$id]="available"
} 