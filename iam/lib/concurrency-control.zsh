#!/bin/zsh

typeset -g TARGET_LATENCY=100  # milliseconds
typeset -g CONCURRENCY_WINDOW=10
typeset -gA LATENCY_HISTORY

adjust_concurrency() {
    local operation=$1
    local duration=$2
    
    # Update sliding window
    LATENCY_HISTORY[$operation]="${LATENCY_HISTORY[$operation]:-} $duration"
    LATENCY_HISTORY[$operation]=${LATENCY_HISTORY[$operation]##* }  # Keep last N values
    
    # Calculate average latency
    local sum=0
    local count=0
    for lat in ${=LATENCY_HISTORY[$operation]}; do
        ((sum += lat))
        ((count++))
    done
    local avg_latency=$((sum / count))
    
    # Adjust concurrency based on latency
    if ((avg_latency > TARGET_LATENCY * 1.2)); then
        MAX_PARALLEL_JOBS=$((MAX_PARALLEL_JOBS * 0.8))
    elif ((avg_latency < TARGET_LATENCY * 0.8)); then
        MAX_PARALLEL_JOBS=$((MAX_PARALLEL_JOBS * 1.2))
    fi
    
    # Ensure bounds
    ((MAX_PARALLEL_JOBS < 1)) && MAX_PARALLEL_JOBS=1
    ((MAX_PARALLEL_JOBS > $(nproc) * 2)) && MAX_PARALLEL_JOBS=$(($(nproc) * 2))
} 