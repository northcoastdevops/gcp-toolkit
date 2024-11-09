#!/bin/zsh

optimize_process() {
    # Set CPU scheduling priority
    renice -n -10 $$ >/dev/null 2>&1
    
    # Set I/O priority
    ionice -c 2 -n 0 -p $$ >/dev/null 2>&1
    
    # Lock process in memory to prevent swapping
    mlockall 2>/dev/null
    
    # Set CPU affinity to use all available cores
    taskset -pc 0-$(( $(nproc) - 1 )) $$ >/dev/null 2>&1
} 