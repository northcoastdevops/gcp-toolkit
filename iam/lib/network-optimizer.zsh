#!/bin/zsh

typeset -gA CONNECTION_POOL
typeset -g KEEPALIVE_INTERVAL=60
typeset -g TCP_RETRIES=3

optimize_network() {
    # Set TCP keepalive
    sysctl -w net.ipv4.tcp_keepalive_time=$KEEPALIVE_INTERVAL 2>/dev/null
    sysctl -w net.ipv4.tcp_keepalive_intvl=15 2>/dev/null
    sysctl -w net.ipv4.tcp_keepalive_probes=5 2>/dev/null
    
    # Optimize TCP settings
    sysctl -w net.ipv4.tcp_fin_timeout=15 2>/dev/null
    sysctl -w net.ipv4.tcp_max_syn_backlog=4096 2>/dev/null
    
    # Set DNS cache
    if command -v nscd >/dev/null; then
        sudo service nscd restart 2>/dev/null
    fi
}

init_connection_pool() {
    local pool_size=${1:-10}
    for ((i=1; i<=pool_size; i++)); do
        # Initialize persistent gcloud connection
        CONNECTION_POOL[$i]=$(gcloud auth print-access-token)
    done
} 