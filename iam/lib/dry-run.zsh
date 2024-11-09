#!/bin/zsh

DRY_RUN=false

simulate_command() {
    local cmd=$1
    
    # Validate input
    if [[ -z "$cmd" ]]; then
        log_error "Empty command provided"
        return 1
    }
    
    # Sanitize command for logging
    local safe_cmd="${cmd//[^[:print:]]/}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "Would execute: $safe_cmd"
        return 0
    else
        if [[ "$cmd" =~ ^[[:space:]]*rm[[:space:]]+-rf[[:space:]]+/ ]]; then
            log_error "Dangerous command detected: $safe_cmd"
            return 1
        fi
        eval "$cmd"
        return $?
    fi
} 