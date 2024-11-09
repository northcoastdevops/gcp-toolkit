#!/bin/zsh

typeset -g CPU_THRESHOLD=80
typeset -g MEMORY_THRESHOLD=80
typeset -g CHECK_INTERVAL=5

monitor_resources() {
    while true; do
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1)
        local mem_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
        
        if ((cpu_usage > CPU_THRESHOLD || mem_usage > MEMORY_THRESHOLD)); then
            # Reduce batch size and parallel jobs
            BATCH_SIZE=$((BATCH_SIZE * 0.75))
            MAX_PARALLEL_JOBS=$((MAX_PARALLEL_JOBS * 0.75))
            log "Reducing load: CPU ${cpu_usage}%, Memory ${mem_usage}%"
        fi
        
        sleep $CHECK_INTERVAL
    done &
} 