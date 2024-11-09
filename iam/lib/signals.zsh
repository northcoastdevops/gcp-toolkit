#!/bin/zsh

handle_interrupt() {
    log_error "Operation interrupted by user"
    cleanup_and_exit 130
}

handle_term() {
    log_error "Operation terminated"
    cleanup_and_exit 143
}

cleanup_and_exit() {
    local exit_code=$1
    
    # Kill any running background jobs
    kill $(jobs -p) 2>/dev/null
    
    # Clean up temporary files
    [[ -f "$TMPFILE" ]] && rm -f "$TMPFILE"
    
    # Release any held locks
    release_all_locks
    
    # Record metrics
    record_metric "script_exit" $SECONDS "$exit_code" "Signal handler"
    
    exit $exit_code
}

trap 'handle_interrupt' INT
trap 'handle_term' TERM
trap 'cleanup_and_exit 0' EXIT 