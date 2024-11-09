#!/bin/zsh

# I/O optimization
typeset -g IO_BUFFER_SIZE=$((16*1024))  # 16KB buffer

optimize_io() {
    # Set larger buffer sizes for file operations
    export TMPDIR="/dev/shm"  # Use RAM disk if available
    
    # Configure file descriptors
    ulimit -n 4096 2>/dev/null  # Increase file descriptor limit
    
    # Set up RAM-based temporary directory
    if [[ -d "/dev/shm" ]]; then
        TEMP_DIR="/dev/shm/gcp-org-tools.$$"
        mkdir -p "$TEMP_DIR"
        export TMPDIR="$TEMP_DIR"
    fi
}

cleanup_io() {
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
} 