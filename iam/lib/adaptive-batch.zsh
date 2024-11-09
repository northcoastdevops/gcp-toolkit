#!/bin/zsh

typeset -g MIN_BATCH_SIZE=5
typeset -g MAX_BATCH_SIZE=50
typeset -gA BATCH_METRICS

adjust_batch_size() {
    local current_time=$SECONDS
    local duration=$1
    local batch_size=$2
    
    # Calculate average processing time
    BATCH_METRICS[total_time]=$((BATCH_METRICS[total_time] + duration))
    BATCH_METRICS[batch_count]=$((BATCH_METRICS[batch_count] + 1))
    local avg_time=$((BATCH_METRICS[total_time] / BATCH_METRICS[batch_count]))
    
    # Adjust batch size based on performance
    if ((duration < avg_time * 0.8)); then
        # Processing is fast, increase batch size
        new_size=$((batch_size * 1.5))
        BATCH_SIZE=$(( new_size > MAX_BATCH_SIZE ? MAX_BATCH_SIZE : new_size ))
    elif ((duration > avg_time * 1.2)); then
        # Processing is slow, decrease batch size
        new_size=$((batch_size * 0.75))
        BATCH_SIZE=$(( new_size < MIN_BATCH_SIZE ? MIN_BATCH_SIZE : new_size ))
    fi
} 