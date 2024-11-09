#!/bin/zsh

# Performance monitoring
declare -A METRICS
SCRIPT_DIR="${SCRIPT_DIR:-$(dirname "${0:A}")}"
METRICS_DIR="${SCRIPT_DIR}/.metrics"
METRICS_FILE="${METRICS_DIR}/$(date +%Y%m%d).log"

# Ensure metrics directory exists with proper permissions
[[ ! -d "$METRICS_DIR" ]] && mkdir -p "$METRICS_DIR" 2>/dev/null
[[ ! -w "$METRICS_DIR" ]] && log_error "Metrics directory is not writable: $METRICS_DIR"

init_metrics() {
    if ! mkdir -p "${SCRIPT_DIR}/.metrics" 2>/dev/null; then
        log_error "Failed to create metrics directory"
        return 1
    }
    
    if [[ ! -w "${SCRIPT_DIR}/.metrics" ]]; then
        log_error "Metrics directory is not writable"
        return 1
    }
    
    METRICS[start_time]=$SECONDS
    return 0
}

record_metric() {
    local operation=$1
    local duration=$2
    local status=$3
    local details=$4
    
    if [[ ! -w "$METRICS_FILE" ]]; then
        log_error "Cannot write to metrics file: $METRICS_FILE"
        return 1
    }
    
    printf "%s\t%s\t%d\t%s\t%s\n" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$operation" \
        "$duration" \
        "$status" \
        "${details:-N/A}" >> "$METRICS_FILE" || {
            log_error "Failed to write metrics"
            return 1
        }
}

summarize_metrics() {
    METRICS[end_time]=$SECONDS
    METRICS[total_duration]=$((METRICS[end_time] - METRICS[start_time]))
    
    log "Performance Summary:"
    log "Total Duration: ${METRICS[total_duration]}s"
    log "API Calls: ${METRICS[api_calls]:-0}"
    log "Cache Hits: ${METRICS[cache_hits]:-0}"
    log "Cache Misses: ${METRICS[cache_misses]:-0}"
    log "Errors: ${METRICS[errors]:-0}"
} 