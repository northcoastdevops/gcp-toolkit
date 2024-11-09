#!/usr/bin/env bash

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
    [[ -d "$HOME/gcp-org-tools.tmp" ]] && rm -rf "$HOME/gcp-org-tools.tmp"
    [[ -d "$HOME/.cache/gcp-org-tools.tmp" ]] && rm -rf "$HOME/.cache/gcp-org-tools.tmp"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect shell
detect_shell() {
    if [[ -n "$ZSH_VERSION" ]]; then
        echo "zsh"
    elif [[ -n "$BASH_VERSION" ]]; then
        echo "bash"
    else
        echo "unknown"
    fi
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
        echo "# GCP Organization Tools"
        echo 'export PATH="$HOME/gcp-org-tools/iam:$PATH"'
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
        "$HOME/gcp-org-tools/iam/query-iam.zsh"
        "$HOME/gcp-org-tools/iam/delete-iam.zsh"
        "$HOME/gcp-org-tools/README.md"
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

# Function to detect current shell
detect_current_shell() {
    echo "$SHELL" | awk -F/ '{print $NF}'
}

# Function to get default shell
get_default_shell() {
    local default_shell
    if [[ "$(uname)" == "Darwin" ]]; then
        default_shell=$(dscl . -read ~/ UserShell | sed 's/UserShell: //')
    else
        default_shell=$(getent passwd $USER | cut -d: -f7)
    fi
    echo "$default_shell" | awk -F/ '{print $NF}'
}

# Function to show shell change warning
show_shell_warning() {
    local current_shell=$(detect_current_shell)
    local default_shell=$(get_default_shell)

    if [[ "$current_shell" != "zsh" && "$default_shell" != "zsh" ]]; then
        clear
        echo -e "${YELLOW}"
        echo "╔═══════��════════════════════════════════════════════════════════╗"
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
        echo -e "(This is required for the GCP Organization Tools)\n"
        
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

# Main installation function
main() {
    echo -e "\n${CYAN}${INFO} GCP Organization Tools Installer${NC}\n"
    
    # Show shell warning first
    show_shell_warning
    
    # Detect shell
    local shell_type=$(detect_shell)
    echo -e "${BLUE}${ARROW} Detected shell: ${NC}$shell_type"
    
    # Detect OS
    local os=$(detect_os)
    local package_manager=$(get_package_manager "$os")
    
    echo -e "${BLUE}${ARROW} Detected OS: ${NC}$os"
    echo -e "${BLUE}${ARROW} Package Manager: ${NC}$package_manager"
    
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
    local packages=("zsh" "jq" "git")
    
    # Add gcloud if not installed
    if ! command_exists gcloud; then
        case $os in
            "macos")
                packages+=("google-cloud-sdk")
                ;;
            *)
                echo -e "\n${YELLOW}${WARN} gcloud CLI needs to be installed manually for your OS${NC}"
                echo -e "Visit: https://cloud.google.com/sdk/docs/install"
                ;;
        esac
    fi
    
    # Show installation plan
    echo -e "\n${BLUE}${INFO} Installation Plan:${NC}"
    echo -e "${BLUE}${ARROW} The following packages will be installed if missing:${NC}"
    printf "  - %s\n" "${packages[@]}"
    echo -e "${BLUE}${ARROW} Installation directory: ${NC}$HOME/gcp-org-tools"
    echo -e "${BLUE}${ARROW} Configuration files will be created in: ${NC}$HOME/.cache/gcp-org-tools"
    echo -e "${BLUE}${ARROW} Shell configuration will be updated in: ${NC}$HOME/.${shell_type}rc"
    
    # Confirm installation
    echo -e "\n${YELLOW}${INFO} This installation will modify your system. Please type 'YES' to confirm:${NC}"
    read -r confirmation
    
    if [[ "$confirmation" != "YES" && "$confirmation" != "yes" ]]; then
        echo -e "\n${RED}${X_MARK} Installation cancelled: User did not confirm${NC}"
        exit 1
    fi
    
    # Begin installation
    echo -e "\n${BLUE}${ARROW} Installing required packages...${NC}"
    install_packages "$package_manager" "${packages[@]}" || {
        echo -e "\n${RED}${X_MARK} Failed to install required packages${NC}"
        exit 1
    }
    
    # Clone repository to temporary location first
    echo -e "\n${BLUE}${ARROW} Cloning repository...${NC}"
    git clone https://github.com/yourusername/gcp-org-tools.git "$HOME/gcp-org-tools.tmp" || {
        echo -e "\n${RED}${X_MARK} Failed to clone repository${NC}"
        exit 1
    }
    
    # Move to final location
    [[ -d "$HOME/gcp-org-tools" ]] && rm -rf "$HOME/gcp-org-tools"
    mv "$HOME/gcp-org-tools.tmp" "$HOME/gcp-org-tools"
    
    # Create cache directory
    echo -e "\n${BLUE}${ARROW} Creating cache directory...${NC}"
    mkdir -p "$HOME/.cache/gcp-org-tools"
    
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
    echo -e "  ~/gcp-org-tools/README.md"
    echo -e "\n${YELLOW}${INFO} Please restart your shell or run:${NC}"
    echo -e "  source ~/.${shell_type}rc"
}

# Run main function
main