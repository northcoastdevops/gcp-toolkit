#!/usr/bin/env zsh

# Ensure running under zsh
if [[ -z "$ZSH_VERSION" ]]; then
    echo -e "\n❌ This script must be run using zsh"
    echo -e "Current shell: $0"
    echo -e "\nTo fix this, you can:"
    echo -e "1. Install zsh: brew install zsh"
    echo -e "2. Run this script with: zsh ./install.sh"
    echo -e "3. Or change your default shell: chsh -s \$(which zsh)\n"
    exit 1
fi

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Icons
CHECK_MARK="✓"
X_MARK="✗"
ARROW="→"
INFO="ℹ"
WARN="⚠"

# Error handling
set -eE  # Exit on error and error in pipes
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

error_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local error_trap_stack=$5
    
    echo -e "\n${RED}${X_MARK} Error occurred in installation:${NC}"
    echo -e "${RED}Command: ${last_command}${NC}"
    echo -e "${RED}Line: ${line_no}${NC}"
    echo -e "${RED}Exit code: ${exit_code}${NC}"
    
    # Cleanup on error
    cleanup_on_error
    
    exit $exit_code
}

# Cleanup function
cleanup_on_error() {
    echo -e "\n${YELLOW}${WARN} Cleaning up incomplete installation...${NC}"
    [[ -d "$HOME/gcp-toolkit.tmp" ]] && rm -rf "$HOME/gcp-toolkit.tmp"
    [[ -d "$HOME/.cache/gcp-toolkit.tmp" ]] && rm -rf "$HOME/.cache/gcp-toolkit.tmp"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect shell
detect_shell() {
    local shell_name

    # Check for ZSH_VERSION or BASH_VERSION environment variables
    if [[ -n "$ZSH_VERSION" ]]; then
        shell_name="zsh"
    elif [[ -n "$BASH_VERSION" ]]; then
        shell_name="bash"
    else
        # Check the parent process shell
        shell_name=$(ps -p $PPID -o comm= | sed 's/-//' | tr -d '\n')
        
        # If still not conclusive, check the login shell
        if [[ -z "$shell_name" || "$shell_name" == "login" ]]; then
            if [[ "$(uname)" == "Darwin" ]]; then
                # macOS specific
                shell_name=$(dscl . -read ~/ UserShell | sed 's/UserShell: //' | awk -F/ '{print $NF}')
            else
                # Linux/Unix
                shell_name=$(getent passwd $USER | cut -d: -f7 | awk -F/ '{print $NF}')
            fi
        fi
    fi

    # Clean up the shell name (remove any path or dash prefix)
    shell_name=$(echo "$shell_name" | sed 's/^-*//' | tr -d '\n')
    
    echo "$shell_name"
}

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# Function to check system requirements
check_system_requirements() {
    local min_memory=1024  # 1GB in MB
    local min_disk=1024    # 1GB in MB
    
    # Check memory
    local total_memory
    if [[ "$(uname)" == "Darwin" ]]; then
        total_memory=$(($(sysctl -n hw.memsize) / 1024 / 1024))
    else
        total_memory=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024))
    fi
    
    # Check disk space
    local available_disk
    if [[ "$(uname)" == "Darwin" ]]; then
        available_disk=$(($(df -k "$HOME" | tail -1 | awk '{print $4}') / 1024))
    else
        available_disk=$(($(df -k "$HOME" | tail -1 | awk '{print $4}') / 1024))
    fi
    
    if [[ $total_memory -lt $min_memory ]]; then
        echo -e "${YELLOW}${WARN} Warning: System has less than 1GB RAM${NC}"
    fi
    
    if [[ $available_disk -lt $min_disk ]]; then
        echo -e "${RED}${X_MARK} Error: Not enough disk space. Need at least 1GB${NC}"
        exit 1
    fi
}

# Function to get package manager
get_package_manager() {
    local os=$1
    case $os in
        "macos")
            if command_exists brew; then
                echo "brew"
            else
                echo "none"
            fi
            ;;
        "ubuntu"|"debian")
            echo "apt-get"
            ;;
        "fedora")
            echo "dnf"
            ;;
        "centos"|"rhel")
            echo "yum"
            ;;
        "arch")
            echo "pacman"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Function to configure shell
configure_shell() {
    local shell_type=$1
    local shell_rc
    
    case $shell_type in
        "zsh")
            shell_rc="$HOME/.zshrc"
            ;;
        "bash")
            shell_rc="$HOME/.bashrc"
            [[ "$(uname)" == "Darwin" ]] && shell_rc="$HOME/.bash_profile"
            ;;
        *)
            echo -e "${YELLOW}${WARN} Unknown shell type. Manual configuration may be required.${NC}"
            return
            ;;
    esac
    
    # Add PATH and aliases if they don't exist
    echo -e "\n${BLUE}${ARROW} Configuring shell environment...${NC}"
    {
        echo ""
        echo "# GCP Toolkit"
        echo 'export PATH="$HOME/gcp-toolkit/iam:$PATH"'
        echo 'alias gcp-query="query-iam.zsh"'
        echo 'alias gcp-delete="delete-iam.zsh"'
    } >> "$shell_rc"
    
    echo -e "${GREEN}${CHECK_MARK} Shell configuration updated in ${shell_rc}${NC}"
}

# Function to install packages
install_packages() {
    local package_manager=$1
    shift
    local packages=("$@")
    
    echo -e "\n${BLUE}${ARROW} Installing packages with ${package_manager}...${NC}"
    
    case $package_manager in
        "brew")
            for package in "${packages[@]}"; do
                if ! brew list "$package" &>/dev/null; then
                    brew install "$package" || return 1
                else
                    echo -e "${GREEN}${CHECK_MARK} ${package} already installed${NC}"
                fi
            done
            ;;
        "apt-get")
            sudo apt-get update
            for package in "${packages[@]}"; do
                if ! dpkg -l "$package" &>/dev/null; then
                    sudo apt-get install -y "$package" || return 1
                else
                    echo -e "${GREEN}${CHECK_MARK} ${package} already installed${NC}"
                fi
            done
            ;;
        "dnf"|"yum")
            for package in "${packages[@]}"; do
                if ! rpm -q "$package" &>/dev/null; then
                    sudo $package_manager install -y "$package" || return 1
                else
                    echo -e "${GREEN}${CHECK_MARK} ${package} already installed${NC}"
                fi
            done
            ;;
        "pacman")
            for package in "${packages[@]}"; do
                if ! pacman -Qi "$package" &>/dev/null; then
                    sudo pacman -Sy --noconfirm "$package" || return 1
                else
                    echo -e "${GREEN}${CHECK_MARK} ${package} already installed${NC}"
                fi
            done
            ;;
    esac
}

# Function to verify installation
verify_installation() {
    echo -e "\n${BLUE}${ARROW} Verifying installation...${NC}"
    
    local required_files=(
        "$HOME/gcp-toolkit/iam/query-iam.zsh"
        "$HOME/gcp-toolkit/iam/delete-iam.zsh"
        "$HOME/gcp-toolkit/README.md"
    )
    
    local required_commands=(
        "zsh"
        "jq"
        "gcloud"
    )
    
    # Check files
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo -e "${GREEN}${CHECK_MARK} Found ${file}${NC}"
        else
            echo -e "${RED}${X_MARK} Missing ${file}${NC}"
            return 1
        fi
    done
    
    # Check commands
    for cmd in "${required_commands[@]}"; do
        if command_exists "$cmd"; then
            echo -e "${GREEN}${CHECK_MARK} Command ${cmd} available${NC}"
        else
            echo -e "${RED}${X_MARK} Command ${cmd} not found${NC}"
            return 1
        fi
    done
}

# Function to get actual running shell
get_running_shell() {
    ps -p $$ -o comm= | sed 's/-//' | tr -d '\n'
}

# Function to show shell change warning
show_shell_warning() {
    local current_shell=$(detect_shell)
    local default_shell=$(get_default_shell)

    if [[ "$current_shell" != "zsh" && "$default_shell" != "zsh" ]]; then
        clear
        echo -e "${YELLOW}"
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║                      IMPORTANT NOTICE                          ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo -e "${CYAN}This installation will change your default shell to zsh${NC}"
        echo -e "\nCurrent shell: ${BLUE}$current_shell${NC}"
        echo -e "Will change to: ${YELLOW}zsh${NC}"
        echo -e "\n${YELLOW}${WARN} This change will affect:${NC}"
        echo "  • Your default shell environment"
        echo "  • Shell startup files"
        echo "  • Command line interface"
        
        echo -e "\n${BLUE}${INFO} To revert back to $current_shell later, you can run:${NC}"
        case "$(uname)" in
            "Darwin")
                echo -e "  chsh -s \$(which $current_shell)"
                ;;
            "Linux")
                echo -e "  chsh -s \$(which $current_shell)"
                [[ "$current_shell" == "bash" ]] && echo "  # or: sudo usermod -s /bin/bash $USER"
                ;;
        esac
        
        echo -e "\n${RED}${WARN} Shell change requires password authentication${NC}"
        
        echo -e "\n${YELLOW}Do you want to proceed with changing your shell to zsh?${NC}"
        echo -e "(This is required for the GCP Toolkit)\n"
        
        while true; do
            read -p "Type 'YES' to proceed or 'NO' to cancel: " shell_confirm
            case $shell_confirm in
                YES)
                    echo -e "\n${GREEN}${CHECK_MARK} Proceeding with installation...${NC}"
                    return 0
                    ;;
                NO)
                    echo -e "\n${RED}${X_MARK} Installation cancelled: Shell change declined${NC}"
                    exit 1
                    ;;
                *)
                    echo -e "${YELLOW}Please type 'YES' or 'NO'${NC}"
                    ;;
            esac
        done
    else
        echo -e "${GREEN}${CHECK_MARK} zsh already configured as shell${NC}"
        return 0
    fi
}

# Add this new function after get_package_manager()
check_installed_packages() {
    local package_manager=$1
    shift
    local -a packages=("$@")
    local -a to_install=()
    
    case $package_manager in
        "brew")
            for package in "${packages[@]}"; do
                if ! brew list "$package" &>/dev/null; then
                    to_install+=("$package")
                fi
            done
            ;;
        "apt-get")
            for package in "${packages[@]}"; do
                if ! dpkg -l "$package" &>/dev/null; then
                    to_install+=("$package")
                fi
            done
            ;;
        "dnf"|"yum")
            for package in "${packages[@]}"; do
                if ! rpm -q "$package" &>/dev/null; then
                    to_install+=("$package")
                fi
            done
            ;;
        "pacman")
            for package in "${packages[@]}"; do
                if ! pacman -Qi "$package" &>/dev/null; then
                    to_install+=("$package")
                fi
            done
            ;;
    esac
    
    echo "${to_install[@]}"
}

# Function to show scanning modal
show_scanning_modal() {
    local current_path="$1"
    tput clear
    tput cup 5 0
    echo -e "╭──────────────────────────────────────────╮"
    echo -e "│         Scanning for GCP Toolkit         │"
    echo -e "├──────────────────────────────────────────┤"
    echo -e "│ Currently scanning:                      │"
    echo -e "│ ${current_path:0:34}               │"
    echo -e "│                                          │"
    echo -e "│ Press ESC to cancel                      │"
    echo -e "╰──────────────────────────────────────────╯"
}

# Function to check repository status
check_repo_status() {
    local install_path="$HOME/gcp-toolkit"
    local current_dir="$(pwd)"
    
    # First check if we're already in a gcp-toolkit repo
    if [[ -d ".git" ]] && [[ -f "install.sh" ]]; then
        local remote_url=$(git config --get remote.origin.url)
        if [[ "$remote_url" =~ gcp-toolkit(\.git)?$ ]]; then
            if [[ "$current_dir" == "$install_path" ]]; then
                echo "current_installed"
            else
                echo "current_different"
            fi
            return
        fi
    fi
    
    # Check home directory installation
    if [[ -d "$install_path" ]]; then
        if [[ -d "$install_path/.git" ]]; then
            echo "exists"
            return
        else
            echo "invalid"
            return
        fi
    fi
    
    echo "missing"
}

# Function for deep repository search
deep_find_existing_repo() {
    local search_paths=(
        "$HOME"
        "$HOME/Documents"
        "$HOME/Projects"
        "$HOME/Development"
        "$HOME/Workspace"
    )
    
    # Set up trap for ESC key
    trap 'exit 1' INT TERM
    trap 'tput cnorm; tput clear; tput cup 0 0; return 1' EXIT
    
    # Hide cursor
    tput civis
    
    for base_path in "${search_paths[@]}"; do
        if [[ -d "$base_path" ]]; then
            find "$base_path" -type d -name ".git" 2>/dev/null | while read gitdir; do
                local repo_dir=$(dirname "$gitdir")
                show_scanning_modal "$repo_dir"
                
                # Check if it's our repo
                if [[ -f "$repo_dir/install.sh" ]]; then
                    local remote_url=$(cd "$repo_dir" && git config --get remote.origin.url)
                    if [[ "$remote_url" =~ gcp-toolkit(\.git)?$ ]]; then
                        echo "$repo_dir"
                        return 0
                    fi
                fi
                
                # Check for ESC key
                read -t 0.1 -N 1 input
                if [[ $input = $'\e' ]]; then
                    return 1
                fi
            done
        fi
    done
}

# Function for interactive repository search
find_repo_interactive() {
    local repo_status="$1"
    
    if [[ "$repo_status" == "missing" ]]; then
        echo -e "\n${BLUE}${INFO} Would you like to scan common locations for an existing installation?${NC}"
        echo -e "The following locations will be searched:"
        echo -e "  • $HOME"
        echo -e "  • $HOME/Documents"
        echo -e "  • $HOME/Projects"
        echo -e "  • $HOME/Development"
        echo -e "  • $HOME/Workspace"
        echo -e "\n${YELLOW}${INFO} This may take a few minutes. (y/N):${NC}"
        read -r scan_response
        
        if [[ "$scan_response" =~ ^[Yy] ]]; then
            echo -e "\n${BLUE}${ARROW} Starting system scan...${NC}"
            local found_path=$(deep_find_existing_repo)
            
            if [[ $? -eq 0 && -n "$found_path" ]]; then
                echo -e "\n${GREEN}${CHECK_MARK} Found existing installation at: $found_path${NC}"
                repo_status="found_elsewhere:$found_path"
            elif [[ $? -eq 1 ]]; then
                echo -e "\n${YELLOW}${INFO} Scan cancelled by user${NC}"
            else
                echo -e "\n${YELLOW}${INFO} No existing installation found${NC}"
            fi
        fi
        
        if [[ "$repo_status" == "missing" ]]; then
            echo -e "\n${BLUE}${INFO} Enter existing installation path (or press ENTER to continue with new installation):${NC}"
            read -r manual_path
            
            if [[ -n "$manual_path" ]]; then
                if [[ -d "$manual_path/.git" ]]; then
                    repo_status="found_elsewhere:$manual_path"
                else
                    echo -e "\n${RED}${X_MARK} Invalid repository path${NC}"
                fi
            fi
        fi
    fi
    
    echo "$repo_status"
}

# Initialize branding
TOOLKIT_VERSION="1.0.0"
TOOLKIT_BANNER="GCP Toolkit Installer v${TOOLKIT_VERSION}"
TOOLKIT_AUTHOR="NorthCoast DevOps"
TOOLKIT_URL="https://www.northcoastdevops.com"

# Function to check if package is installed
is_package_installed() {
    local package=$1
    local os=$2
    local package_manager=$3

    # First check if command exists (for executable packages)
    if command_exists "$package"; then
        return 0
    fi

    # Then check package manager specific
    case $package_manager in
        "brew")
            brew list "$package" &>/dev/null
            return $?
            ;;
        "apt-get")
            dpkg -l "$package" &>/dev/null
            return $?
            ;;
        *)
            return 1
            ;;
    esac
}

# Add new function to prompt for installation location
prompt_install_location() {
    local default_path="$HOME/gcp-toolkit"
    
    echo -e "\n${BLUE}${INFO} Repository Installation Location:${NC}"
    echo -e "  Default: $default_path"
    echo -e "  Repository: $REPO_URL"
    echo -e "\n${YELLOW}${INFO} Press ENTER to use default or type custom path:${NC}"
    read -r custom_path
    
    if [[ -z "$custom_path" ]]; then
        echo "$default_path"
    else
        # Clean up path (remove trailing slash, expand ~)
        custom_path="${custom_path%/}"
        custom_path="${custom_path/#\~/$HOME}"
        echo "$custom_path"
    fi
}

# Update the repository URL constant at the top of the file
REPO_URL="https://github.com/northcoastdevops/gcp-toolkit.git"

# Main installation function
main() {
    # Welcome message
    echo -e "\n${CYAN}${TOOLKIT_BANNER}${NC}"
    echo -e "${BLUE}${INFO} By ${TOOLKIT_AUTHOR} (${TOOLKIT_URL})${NC}\n"

    # Perform pre-installation checks WITHOUT making any changes
    local os=$(detect_os)
    local shell_type=$(detect_shell)
    local package_manager=$(get_package_manager "$os")
    
    # Show system information
    echo -e "${BLUE}${INFO} System Information:${NC}"
    echo -e "  • Operating System: $os"
    echo -e "  • Shell: $shell_type"
    echo -e "  • Package Manager: $package_manager\n"

    # Initialize empty arrays for required and missing packages
    local -a required_packages=()
    local -a missing_packages=()

    # Check each potential requirement with detailed logging
    echo -e "\n${BLUE}${INFO} Checking installed packages...${NC}"
    
    if ! is_package_installed "zsh" "$os" "$package_manager"; then
        echo -e "  ${YELLOW}${ARROW} zsh not found${NC}"
        required_packages+=("zsh")
        missing_packages+=("zsh")
    else
        echo -e "  ${GREEN}${CHECK_MARK} zsh already installed${NC}"
    fi
    
    if ! is_package_installed "jq" "$os" "$package_manager"; then
        echo -e "  ${YELLOW}${ARROW} jq not found${NC}"
        required_packages+=("jq")
        missing_packages+=("jq")
    else
        echo -e "  ${GREEN}${CHECK_MARK} jq already installed${NC}"
    fi
    
    if ! is_package_installed "git" "$os" "$package_manager"; then
        echo -e "  ${YELLOW}${ARROW} git not found${NC}"
        required_packages+=("git")
        missing_packages+=("git")
    else
        echo -e "  ${GREEN}${CHECK_MARK} git already installed${NC}"
    fi
    
    if ! command_exists gcloud; then
        if [[ "$os" == "macos" ]] && ! brew list google-cloud-sdk &>/dev/null; then
            echo -e "  ${YELLOW}${ARROW} google-cloud-sdk not found${NC}"
            required_packages+=("google-cloud-sdk")
            missing_packages+=("google-cloud-sdk")
        else
            echo -e "  ${GREEN}${CHECK_MARK} gcloud already installed${NC}"
        fi
    else
        echo -e "  ${GREEN}${CHECK_MARK} gcloud already installed${NC}"
    fi

    echo -e ""

    # Prompt for installation location
    local install_path=$(prompt_install_location)
    
    # Check repository status with custom path
    echo -e "\n${BLUE}${INFO} Checking for existing repository...${NC}"
    local repo_status=$(check_repo_status "$install_path")
    
    # Update check_repo_status function to use custom path
    if [[ -d "$install_path" ]]; then
        if [[ -d "$install_path/.git" ]]; then
            # Verify it's our repository
            local remote_url=$(cd "$install_path" && git config --get remote.origin.url)
            if [[ "$remote_url" =~ northcoastdevops/gcp-toolkit(\.git)?$ ]]; then
                echo "exists"
            else
                echo "invalid"
            fi
        else
            echo "invalid"
        fi
    else
        echo "missing"
    fi
    
    # Update installation plan to use custom path
    case "$repo_status" in
        "current_installed")
            echo -e "  ${GREEN}${CHECK_MARK} Repository already in correct location${NC}"
            ;;
        "current_different")
            echo -e "  $step. Move repository to $install_path"
            ((step++))
            will_modify_system=true
            ;;
        "exists")
            echo -e "  ${GREEN}${CHECK_MARK} Repository already installed at $install_path${NC}"
            ;;
        "found_elsewhere:"*)
            local existing_path="${repo_status#*:}"
            echo -e "  $step. Move repository from ${existing_path} to $install_path"
            ((step++))
            will_modify_system=true
            ;;
        "invalid")
            echo -e "  $step. Remove invalid installation and clone repository to $install_path"
            ((step++))
            will_modify_system=true
            ;;
        "missing")
            echo -e "  $step. Clone repository to $install_path"
            ((step++))
            will_modify_system=true
            ;;
    esac
    
    # Show remaining steps
    echo -e "  $step. Configure shell environment"
    ((step++))
    echo -e "  $step. Set up cache and backup directories\n"

    # Store the packages array for later use
    packages=("${missing_packages[@]}")

    # Prompt for installation with clear warning
    echo -e "${YELLOW}${WARN} This installation will modify your system:${NC}"
    echo -e "  • Install required packages"
    echo -e "  • Create directories in your home folder"
    echo -e "  • Modify your shell configuration"
    echo -e "\n${YELLOW}${INFO} Type 'YES' to proceed with installation:${NC}"
    read -r confirmation

    if [[ "$confirmation" != "YES" ]]; then
        echo -e "\n${RED}${X_MARK} Installation cancelled: User did not confirm${NC}"
        exit 1
    fi

    # Only after confirmation, proceed with actual installation
    echo -e "\n${BLUE}${ARROW} Beginning installation...${NC}"
    
    # Check system requirements
    check_system_requirements
    
    # Handle macOS Homebrew installation
    if [[ "$os" == "macos" && "$package_manager" == "none" ]]; then
        echo -e "\n${YELLOW}${INFO} Homebrew is not installed. It's required for package management on macOS.${NC}"
        echo -e "${YELLOW}${ARROW} Would you like to install Homebrew? This will run:${NC}"
        echo -e "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        
        read -p "Install Homebrew? (yes/NO): " install_brew
        if [[ "$install_brew" == "yes" ]]; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            package_manager="brew"
        else
            echo -e "\n${RED}${X_MARK} Installation cancelled: Homebrew is required${NC}"
            exit 1
        fi
    fi
    
    # Required packages
    local -a base_packages=("zsh" "jq" "git")
    local -a packages=()
    
    # Check which packages need to be installed
    if [[ -n "$package_manager" && "$package_manager" != "unknown" ]]; then
        packages=($(check_installed_packages "$package_manager" "${base_packages[@]}"))
    else
        packages=("${base_packages[@]}")
    fi
    
    # Add gcloud if not installed
    if ! command_exists gcloud; then
        case $os in
            "macos")
                if ! brew list google-cloud-sdk &>/dev/null; then
                    packages+=("google-cloud-sdk")
                fi
                ;;
            *)
                echo -e "\n${YELLOW}${WARN} gcloud CLI needs to be installed manually for your OS${NC}"
                echo -e "Visit: https://cloud.google.com/sdk/docs/install"
                ;;
        esac
    fi
    
    # Show installation plan
    echo -e "\n${BLUE}${INFO} Installation Plan:${NC}"
    if [[ ${#packages[@]} -eq 0 ]]; then
        echo -e "${GREEN}${CHECK_MARK} All required packages are already installed${NC}"
    else
        echo -e "${BLUE}${ARROW} The following packages will be installed:${NC}"
        printf "  - %s\n" "${packages[@]}"
    fi
    
    # Clone repository to temporary location first
    echo -e "\n${BLUE}${ARROW} Cloning repository...${NC}"
    git clone "$REPO_URL" "${install_path}.tmp" || {
        echo -e "\n${RED}${X_MARK} Failed to clone repository${NC}"
        exit 1
    }
    
    # Move to final location
    [[ -d "$install_path" ]] && rm -rf "$install_path"
    mv "${install_path}.tmp" "$install_path"
    
    # Create cache directory
    echo -e "\n${BLUE}${ARROW} Creating cache directory...${NC}"
    mkdir -p "$HOME/.cache/gcp-toolkit"
    
    # Configure shell
    configure_shell "$shell_type"
    
    # Verify installation
    verify_installation || {
        echo -e "\n${RED}${X_MARK} Installation verification failed${NC}"
        exit 1
    }
    
    # Installation complete
    echo -e "\n${GREEN}${CHECK_MARK} Installation complete!${NC}"
    
    # Show usage instructions
    echo -e "\n${BLUE}${INFO} Quick Start Guide:${NC}"
    echo -e "${BLUE}${ARROW} First, authenticate with Google Cloud:${NC}"
    echo -e "  gcloud auth login"
    echo -e "  gcloud config set project YOUR_PROJECT_ID"
    echo -e "\n${BLUE}${ARROW} Query IAM permissions:${NC}"
    echo -e "  gcp-query --org-id YOUR_ORG_ID --list-users"
    echo -e "\n${BLUE}${ARROW} Delete IAM permissions (with backup):${NC}"
    echo -e "  gcp-delete --email user@domain.com --confirm"
    echo -e "\n${BLUE}${INFO} For detailed documentation, see:${NC}"
    echo -e "  ~/gcp-toolkit/README.md"
    echo -e "\n${YELLOW}${INFO} Please restart your shell or run:${NC}"
    echo -e "  source ~/.${shell_type}rc"
}

# Run main function
main