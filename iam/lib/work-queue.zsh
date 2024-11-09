#!/bin/zsh

typeset -gA WORK_QUEUES
typeset -g QUEUE_COUNT=4  # Number of queues (adjust based on CPU cores)

init_work_queues() {
    for ((i=1; i<=QUEUE_COUNT; i++)); do
        WORK_QUEUES[$i]=()
    }
}

distribute_work() {
    local items=($@)
    local current_queue=1
    
    for item in $items; do
        WORK_QUEUES[$current_queue]+=$item
        ((current_queue++))
        [[ $current_queue -gt $QUEUE_COUNT ]] && current_queue=1
    done
}

steal_work() {
    local worker_id=$1
    local max_steal=$(( ${#WORK_QUEUES[1]} / 2 ))
    
    # Find busiest queue
    local busiest_queue=1
    local max_size=${#WORK_QUEUES[1]}
    
    for ((i=2; i<=QUEUE_COUNT; i++)); do
        if ((${#WORK_QUEUES[$i]} > max_size)); then
            busiest_queue=$i
            max_size=${#WORK_QUEUES[$i]}
        fi
    done
    
    # Steal work if worthwhile
    if ((max_size > max_steal)); then
        local stolen=(${WORK_QUEUES[$busiest_queue][1,$max_steal]})
        WORK_QUEUES[$busiest_queue]=(${WORK_QUEUES[$busiest_queue][$max_steal+1,-1]})
        WORK_QUEUES[$worker_id]+=$stolen
        return 0
    fi
    
    return 1
} 