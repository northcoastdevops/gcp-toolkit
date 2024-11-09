#!/bin/zsh

# Memory management
typeset -g MAX_MEMORY_MB=1024
typeset -g MEMORY_CHECK_INTERVAL=60

check_memory_usage() {
    local pid=$1
    local memory_kb=$(ps -o rss= -p $pid)
    local memory_mb=$((memory_kb / 1024))
    
    if ((memory_mb > MAX_MEMORY_MB)); then
        log_error "Memory usage exceeded ${MAX_MEMORY_MB}MB limit"
        return 1
    fi
    return 0
}

start_memory_monitor() {
    # Kill any existing monitor
    [[ -n "$MEMORY_MONITOR_PID" ]] && kill $MEMORY_MONITOR_PID 2>/dev/null
    
    while true; do
        if ! check_memory_usage $$; then
            log_error "Memory limit exceeded, initiating cleanup"
            cleanup_and_exit 1
        fi
        sleep $MEMORY_CHECK_INTERVAL
    done &
    MEMORY_MONITOR_PID=$!
    
    # Ensure monitor is cleaned up
    trap 'kill $MEMORY_MONITOR_PID 2>/dev/null' EXIT
} 