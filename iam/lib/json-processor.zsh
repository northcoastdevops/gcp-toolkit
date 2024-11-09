#!/bin/zsh

# JSON processing optimization
typeset -g JQ_BATCH_SIZE=1000

process_policies_stream() {
    local input_file=$1
    local output_file=$2
    local filter=$3
    
    # Process JSON as a stream for memory efficiency
    jq -cnr --stream \
        --arg filter "$filter" \
        '
        fromstream(1|truncate_stream(inputs))
        | select(.bindings != null)
        | .bindings[]
        | select(.members != null)
        | .role as $role
        | .members[]
        | select(contains($filter))
        ' "$input_file" > "$output_file"
} 