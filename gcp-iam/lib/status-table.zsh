#!/bin/zsh

# Shared status table configuration
typeset -g TERM_HEIGHT=$(tput lines)
typeset -g TERM_WIDTH=$(tput cols)
typeset -g TABLE_HEIGHT=$(( TERM_HEIGHT * 50 / 100 ))
typeset -g MAX_VISIBLE_ROWS=$(( TABLE_HEIGHT - 6 ))
typeset -g SPINNER_CHARS=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
typeset -g SPINNER_IDX=0
typeset -g TABLE_START_POS=0

# Operation status configuration
typeset -g OPERATION_LOG=()
typeset -g MAX_OPERATION_LINES=5
typeset -g OPERATION_BOX_START=0
typeset -g OPERATION_BOX_HEIGHT=7  # Header + 5 lines + footer

# Initialize status table
init_status_table() {
    local title=$1
    local columns=("${@:2}")  # Array of column names
    
    # Store column configuration
    TABLE_COLUMNS=("${columns[@]}")
    
    # Clear screen and move to top
    echo -ne '\033[2J\033[H'
    
    # Save initial position
    echo -ne '\033[s'
    TABLE_START_POS=$(tput lines)
    
    # Draw the fixed table structure
    draw_table_frame "$title" "${columns[@]}"
}

# Draw the fixed table frame
draw_table_frame() {
    local title=$1
    local columns=("${@:2}")
    local num_cols=${#columns}
    
    # Store current title
    CURRENT_TITLE="$title"
    
    printf "%s\n\n" "$title"
    
    # Calculate column widths
    local -a col_widths
    local remaining_width=$((TERM_WIDTH - num_cols - 1))
    local base_width=$((remaining_width / num_cols))
    
    # Ensure minimum column width
    if ((base_width < 10)); then
        base_width=10
        log "Warning: Terminal too narrow, table may not display correctly"
    fi
    
    # Store column widths globally
    TABLE_COL_WIDTHS=()
    for col in "${columns[@]}"; do
        TABLE_COL_WIDTHS+=($base_width)
    done
    
    # Draw top border
    printf "┌"
    for ((i=0; i<num_cols; i++)); do
        printf "%s" "$(printf '%*s' ${TABLE_COL_WIDTHS[i]} '' | tr ' ' '─')"
        [[ $i -lt $((num_cols-1)) ]] && printf "┬" || printf "┐\n"
    done
    
    # Draw header
    printf "│"
    for ((i=0; i<num_cols; i++)); do
        printf " %-$((TABLE_COL_WIDTHS[i]-2))s " "${columns[i]}"
        printf "│"
    done
    printf "\n"
    
    # Draw separator
    printf "├"
    for ((i=0; i<num_cols; i++)); do
        printf "%s" "$(printf '%*s' ${TABLE_COL_WIDTHS[i]} '' | tr ' ' '─')"
        [[ $i -lt $((num_cols-1)) ]] && printf "┼" || printf "┤\n"
    done
    
    # Draw empty rows
    for ((row=0; row<MAX_VISIBLE_ROWS; row++)); do
        printf "│"
        for ((i=0; i<num_cols; i++)); do
            printf " %-$((TABLE_COL_WIDTHS[i]-2))s " ""
            printf "│"
        done
        printf "\n"
    done
    
    # Draw bottom border
    printf "└"
    for ((i=0; i<num_cols; i++)); do
        printf "%s" "$(printf '%*s' ${TABLE_COL_WIDTHS[i]} '' | tr ' ' '─')"
        [[ $i -lt $((num_cols-1)) ]] && printf "┴" || printf "┘\n"
    done
}

# Update a specific row
update_table_row() {
    local row=$1
    shift
    local values=("$@")
    
    if ((row >= 0 && row < MAX_VISIBLE_ROWS)); then
        # Calculate position
        local pos=$((row + 4))
        
        # Move to row
        echo -ne "\033[${pos};1H\033[K"
        
        # Print row content
        printf "│"
        for ((i=0; i<${#values[@]}; i++)); do
            printf " %-$((TABLE_COL_WIDTHS[i]-2))s " "${values[i]}"
            printf "│"
        done
    fi
}

# Clear a specific row
clear_table_row() {
    local row=$1
    update_table_row $row "" "" ""
}

# Update progress information
update_progress() {
    local total=$1
    local completed=$2
    local active=$3
    local max_jobs=$4
    
    # Move to end of table
    echo -ne "\033[${TABLE_START_POS};1H"
    
    # Progress bar
    local percent=$((completed * 100 / total))
    local bar_width=50
    local filled=$((bar_width * percent / 100))
    local empty=$((bar_width - filled))
    
    printf "Overall Progress: %3d%% [%s%s]\n" \
        "$percent" \
        "$(printf '%*s' $filled '' | tr ' ' '█')" \
        "$(printf '%*s' $empty '' | tr ' ' '░')"
    
    printf "Completed: %d/%d items\n" "$completed" "$total"
    printf "Active Jobs: %d/%d (Max: %d)" "$active" "$total" "$max_jobs"
    
    if ((active > MAX_VISIBLE_ROWS)); then
        printf " (%d more jobs not shown)" $((active - MAX_VISIBLE_ROWS))
    fi
    printf "\n"
}

# Get next spinner character
get_spinner() {
    SPINNER_IDX=$(( (SPINNER_IDX + 1) % ${#SPINNER_CHARS[@]} ))
    echo "${SPINNER_CHARS[$SPINNER_IDX]}"
}

# Initialize operation status area
init_operation_status() {
    # Calculate position below main status table
    OPERATION_BOX_START=$((TABLE_START_POS + 5))  # After progress display
    
    # Move to operation box position
    echo -ne "\033[${OPERATION_BOX_START};1H"
    
    # Draw operation box
    printf "\n┌─ Current Operations "
    printf "%s" "$(printf '%*s' $((TERM_WIDTH - 21)) '' | tr ' ' '─')"
    printf "┐\n"
    
    for ((i=0; i<5; i++)); do
        printf "│ %-$((TERM_WIDTH - 3))s │\n" ""
    done
    
    printf "└%s┘\n" "$(printf '%*s' $((TERM_WIDTH - 3)) '' | tr ' ' '─')"
    
    # Save position for updates
    OPERATION_BOX_START=$((OPERATION_BOX_START + 2))  # After box header
}

# Update operation status
update_operation_status() {
    local message=$1
    local timestamp=$(date +'%H:%M:%S')
    
    # Add new message to log
    OPERATION_LOG=("[$timestamp] $message" "${OPERATION_LOG[@]}")
    
    # Trim log to maximum size
    if ((${#OPERATION_LOG[@]} > 5)); then
        OPERATION_LOG=(${OPERATION_LOG[@]:0:5})
    fi
    
    # Move to first operation line
    echo -ne "\033[${OPERATION_BOX_START};1H"
    
    # Update each line
    for ((i=0; i<5; i++)); do
        echo -ne "\033[K"  # Clear line
        if ((i < ${#OPERATION_LOG[@]})); then
            printf "│ %-$((TERM_WIDTH - 3))s │\n" "${OPERATION_LOG[i]}"
        else
            printf "│ %-$((TERM_WIDTH - 3))s │\n" ""
        fi
    done
}

# Add new function
handle_resize() {
    TERM_HEIGHT=$(tput lines)
    TERM_WIDTH=$(tput cols)
    
    if ((TERM_WIDTH < MIN_TERM_WIDTH || TERM_HEIGHT < MIN_TERM_HEIGHT)); then
        log "Warning: Terminal size ${TERM_WIDTH}x${TERM_HEIGHT} is below minimum ${MIN_TERM_WIDTH}x${MIN_TERM_HEIGHT}"
    fi
    
    TABLE_HEIGHT=$(( TERM_HEIGHT * 50 / 100 ))
    MAX_VISIBLE_ROWS=$(( TABLE_HEIGHT - 6 ))
    redraw_display
}

# Add new function
redraw_display() {
    # Save cursor
    echo -ne '\033[s'
    
    # Clear screen and redraw
    echo -ne '\033[2J\033[H'
    draw_table_frame "$CURRENT_TITLE" "${TABLE_COLUMNS[@]}"
    init_operation_status
    
    # Restore cursor
    echo -ne '\033[u'
}

# Add after other configuration
trap handle_resize WINCH