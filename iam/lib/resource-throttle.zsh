#!/bin/zsh

typeset -g LOAD_THRESHOLD=0.8
typeset -g IO_THRESHOLD=0.7
typeset -g NET_THRESHOLD=0.6

check_system_load() {
    local cpu_load=$(uptime | awk '{print $(NF-2)}' | tr -d ',')
    local io_wait=$(iostat -c 1 2 | tail -n 1 | awk '{print $4}')
    local net_util=$(netstat -i | grep -v face | awk '{print $3 + $7}' | sort -nr | head -n 1)
    
    local throttle=1.0
    
    # CPU throttling
    if (( cpu_load > LOAD_THRESHOLD * $(nproc) )); then
        throttle=$(( throttle * 0.8 ))
    fi
    
    # IO throttling
    if (( io_wait > IO_THRESHOLD * 100 )); then
        throttle=$(( throttle * 0.7 ))
    fi
    
    # Network throttling
    if (( net_util > NET_THRESHOLD * 1000000 )); then
        throttle=$(( throttle * 0.6 ))
    fi
    
    echo $throttle
}

apply_throttle() {
    local throttle=$(check_system_load)
    
    # Adjust batch and concurrency settings
    BATCH_SIZE=$(( BATCH_SIZE * throttle ))
    MAX_PARALLEL_JOBS=$(( MAX_PARALLEL_JOBS * throttle ))
    
    # Ensure minimums
    ((BATCH_SIZE < MIN_BATCH_SIZE)) && BATCH_SIZE=$MIN_BATCH_SIZE
    ((MAX_PARALLEL_JOBS < 1)) && MAX_PARALLEL_JOBS=1
} 