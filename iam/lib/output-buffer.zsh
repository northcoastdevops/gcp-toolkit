#!/bin/zsh

typeset -g BUFFER_SIZE=$((1024 * 1024))  # 1MB
typeset -g FLUSH_THRESHOLD=$((BUFFER_SIZE * 0.8))
typeset -g OUTPUT_BUFFER=""

buffer_output() {
    local output="$1"
    OUTPUT_BUFFER+="$output"
    
    if ((${#OUTPUT_BUFFER} >= FLUSH_THRESHOLD)); then
        flush_buffer
    fi
}

flush_buffer() {
    if [[ -n "$OUTPUT_BUFFER" ]]; then
        echo -n "$OUTPUT_BUFFER"
        OUTPUT_BUFFER=""
    fi
} 