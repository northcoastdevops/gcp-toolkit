#!/bin/zsh

# Import the status table library
source "${${(%):-%x}:h}/status-table.zsh"

# Parallel processing configuration
typeset -gA PARALLEL_JOBS
typeset -g MAX_PARALLEL_JOBS=10
typeset -g PARALLEL_SLEEP_INTERVAL=0.1
typeset -g TOTAL_JOBS=0
typeset -g COMPLETED_JOBS=0

# Add at top with other globals
typeset -gA JOB_STATUS
typeset -g JOB_TIMEOUT=300  # 5 minutes default timeout

# Add after existing globals
typeset -g BATCH_SIZE=5  # Process jobs in batches
typeset -gA BATCH_QUEUE

# Initialize parallel processing
init_parallel_processor() {
    local title=$1
    local max_jobs=${2:-$MAX_PARALLEL_JOBS}
    
    MAX_PARALLEL_JOBS=$max_jobs
    TOTAL_JOBS=0
    COMPLETED_JOBS=0
    PARALLEL_JOBS=()
    
    # Redirect output
    exec 3>&1
    exec 1>/dev/null
    exec 4>&2
    exec 2>/dev/null
    
    # Clear screen and initialize displays
    clear
    init_status_table "$title" "Job ID" "Status" "Progress"
    init_operation_status
}

# Add job to parallel queue
add_parallel_job() {
    local job_id=$1
    local cmd=$2
    shift 2
    local args=("$@")
    
    ((TOTAL_JOBS++))
    
    # Wait if at max jobs
    while ((${#PARALLEL_JOBS[@]} >= MAX_PARALLEL_JOBS)); do
        check_parallel_jobs
        sleep $PARALLEL_SLEEP_INTERVAL
    done
    
    # Start new job with timeout
    {
        update_operation_status "Starting job: $job_id"
        if ! timeout $JOB_TIMEOUT eval "$cmd ${args[@]}" &>/dev/null; then
            local status=$?
            if ((status == 124)); then  # timeout exit code
                JOB_STATUS[$job_id]="timeout"
                update_operation_status "Timeout: $job_id (exceeded ${JOB_TIMEOUT}s)"
            else
                JOB_STATUS[$job_id]="failed"
                update_operation_status "Failed job: $job_id (error $status)"
            fi
        else
            JOB_STATUS[$job_id]="completed"
            update_operation_status "Completed job: $job_id"
        fi
    } &
    
    PARALLEL_JOBS[$!]=$job_id
    JOB_STATUS[$job_id]="running"
    update_displays
}

# Check and cleanup completed jobs
check_parallel_jobs() {
    local completed_pids=()
    
    for pid in "${(k)PARALLEL_JOBS[@]}"; do
        if ! kill -0 $pid 2>/dev/null; then
            wait $pid 2>/dev/null
            completed_pids+=($pid)
            ((COMPLETED_JOBS++))
        fi
    done
    
    for pid in $completed_pids; do
        unset "PARALLEL_JOBS[$pid]"
    done
    
    update_displays
}

# Update all displays
update_displays() {
    # Update job status table
    local row=0
    for pid in "${(k)PARALLEL_JOBS[@]}"; do
        if ((row >= MAX_VISIBLE_ROWS)); then
            break
        fi
        
        local job_id="${PARALLEL_JOBS[$pid]}"
        local spinner=$(get_spinner)
        local status="${JOB_STATUS[$job_id]}"
        
        case "$status" in
            "failed")
                update_table_row $row "$job_id" "Failed ✗" "Error"
                ;;
            "timeout")
                update_table_row $row "$job_id" "Timeout ⏰" "Hung"
                ;;
            "completed")
                update_table_row $row "$job_id" "Complete ✓" "Done"
                ;;
            *)
                update_table_row $row "$job_id" "Running" "$spinner Processing..."
                ;;
        esac
        ((row++))
    done
    
    # Clear remaining rows
    while ((row < MAX_VISIBLE_ROWS)); do
        clear_table_row $row
        ((row++))
    done
    
    # Update progress
    update_progress \
        $TOTAL_JOBS \
        $COMPLETED_JOBS \
        ${#PARALLEL_JOBS[@]} \
        $MAX_PARALLEL_JOBS
}

# Wait for all jobs to complete
wait_for_jobs() {
    while ((${#PARALLEL_JOBS[@]} > 0)); do
        check_parallel_jobs
        sleep $PARALLEL_SLEEP_INTERVAL
    done
    
    # Restore output
    exec 1>&3 3>&-
    exec 2>&4 4>&-
    
    echo
}

batch_jobs() {
    local current_batch=()
    
    # Check if queue exists and has items
    if [[ -z "${BATCH_QUEUE}" ]] || [[ ${#BATCH_QUEUE[@]} -eq 0 ]]; then
        log_error "Empty batch queue"
        return 1
    }
    
    # Fill current batch
    while ((${#current_batch[@]} < BATCH_SIZE)) && ((${#BATCH_QUEUE[@]} > 0)); do
        local next_job=${(k)BATCH_QUEUE[1]}
        [[ -n "$next_job" ]] || break  # Break if next_job is empty
        current_batch+=($next_job)
        unset "BATCH_QUEUE[$next_job]"
    done
    
    # Verify batch has items
    [[ ${#current_batch[@]} -eq 0 ]] && return 0
    
    # Process batch in parallel
    for job in $current_batch; do
        start_job $job
    done
    
    wait_for_batch $current_batch
} 