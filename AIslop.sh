#!/bin/bash
set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[1;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

heading() {
    echo -e "${BLUE}${BOLD}$*${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root. Use: sudo $0"
    fi
}

# Detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="$ID"
    else
        error "Cannot detect operating system"
    fi

    case "$OS" in
        ubuntu|debian)
            PKG_MANAGER="apt"
            ;;
        fedora|rhel|centos)
            PKG_MANAGER="dnf"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            ;;
        *)
            warning "Unsupported OS: $OS, will attempt generic removal"
            PKG_MANAGER="unknown"
            ;;
    esac

    info "Detected OS: $OS (Package manager: $PKG_MANAGER)"
}

# Stop and disable cloudflared service
stop_cloudflared_service() {
    heading "Stopping Cloudflared Services..."
    
    local stopped=false
    
    # Try to stop the service
    if systemctl is-active cloudflared >/dev/null 2>&1; then
        info "Stopping cloudflared service..."
        systemctl stop cloudflared || warning "Failed to stop cloudflared service"
        stopped=true
    fi
    
    # Disable the service
    if systemctl is-enabled cloudflared >/dev/null 2>&1; then
        info "Disabling cloudflared service..."
        systemctl disable cloudflared || warning "Failed to disable cloudflared service"
        stopped=true
    fi
    
    if [ "$stopped" = false ]; then
        info "No active cloudflared service found"
    fi
}

# Remove cloudflared package
remove_cloudflared_package() {
    heading "Removing Cloudflared Package..."
    
    case "$PKG_MANAGER" in
        apt)
            if dpkg -l | grep -q cloudflared; then
                info "Removing cloudflared package..."
                apt-get remove --purge -y cloudflared
                apt-get autoremove -y
                info "Package removed successfully"
            else
                info "Cloudflared package not installed"
            fi
            ;;
        dnf)
            if rpm -q cloudflared >/dev/null 2>&1; then
                info "Removing cloudflared package..."
                dnf remove -y cloudflared
                info "Package removed successfully"
            else
                info "Cloudflared package not installed"
            fi
            ;;
        pacman)
            if pacman -Q cloudflared >/dev/null 2>&1; then
                info "Removing cloudflared package..."
                pacman -Rns --noconfirm cloudflared
                info "Package removed successfully"
            else
                info "Cloudflared package not installed"
            fi
            ;;
        *)
            warning "Unknown package manager, skipping package removal"
            ;;
    esac
}

# Remove cloudflared repositories
remove_cloudflared_repos() {
    heading "Removing Cloudflared Repositories..."
    
    local removed=false
    
    # Remove apt repository
    if [ -f /etc/apt/sources.list.d/cloudflared.list ]; then
        info "Removing cloudflared apt repository..."
        rm -f /etc/apt/sources.list.d/cloudflared.list
        removed=true
    fi
    
    # Remove cloudflare keyring
    if [ -f /usr/share/keyrings/cloudflare-archive-keyring.gpg ]; then
        info "Removing cloudflare keyring..."
        rm -f /usr/share/keyrings/cloudflare-archive-keyring.gpg
        removed=true
    fi
    
    # Remove DNF/YUM repo
    if [ -f /etc/yum.repos.d/cloudflared.repo ]; then
        info "Removing cloudflared yum repository..."
        rm -f /etc/yum.repos.d/cloudflared.repo
        removed=true
    fi
    
    if [ "$removed" = true ]; then
        if [ "$PKG_MANAGER" = "apt" ]; then
            info "Updating package lists..."
            apt-get update
        fi
    else
        info "No cloudflared repositories found"
    fi
}

# Remove cloudflared configuration files
remove_cloudflared_configs() {
    heading "Removing Cloudflared Configuration Files..."
    
    local removed=false
    
    # Common cloudflared directories
    local dirs=(
        "/etc/cloudflared"
        "/usr/local/etc/cloudflared"
        "$HOME/.cloudflared"
        "/root/.cloudflared"
    )
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            info "Removing $dir..."
            rm -rf "$dir"
            removed=true
        fi
    done
    
    # Remove systemd service files
    if [ -f /etc/systemd/system/cloudflared.service ]; then
        info "Removing systemd service file..."
        rm -f /etc/systemd/system/cloudflared.service
        systemctl daemon-reload
        removed=true
    fi
    
    if [ "$removed" = false ]; then
        info "No cloudflared configuration files found"
    fi
}

# Remove cloudflared binary (if manually installed)
remove_cloudflared_binary() {
    heading "Checking for Manually Installed Binary..."
    
    local removed=false
    
    # Common binary locations
    local bins=(
        "/usr/local/bin/cloudflared"
        "/usr/bin/cloudflared"
        "/opt/cloudflared/cloudflared"
    )
    
    for bin in "${bins[@]}"; do
        if [ -f "$bin" ]; then
            info "Removing $bin..."
            rm -f "$bin"
            removed=true
        fi
    done
    
    if [ "$removed" = false ]; then
        info "No manually installed binaries found"
    fi
}

# Final cleanup
final_cleanup() {
    heading "Performing Final Cleanup..."
    
    # Remove any leftover processes
    if pgrep -x cloudflared >/dev/null; then
        warning "Cloudflared process still running, killing..."
        pkill -9 cloudflared || true
    fi
    
    # Clean up package cache
    case "$PKG_MANAGER" in
        apt)
            apt-get clean
            ;;
        dnf)
            dnf clean all
            ;;
        pacman)
            pacman -Sc --noconfirm
            ;;
    esac
    
    info "Cleanup complete"
}

# Verify removal
verify_removal() {
    heading "Verifying Removal..."
    
    local issues=0
    
    # Check for binary
    if command -v cloudflared >/dev/null 2>&1; then
        warning "cloudflared binary still found in PATH"
        ((issues++))
    else
        info "✓ Binary removed"
    fi
    
    # Check for service
    if systemctl list-unit-files | grep -q cloudflared; then
        warning "cloudflared service still exists"
        ((issues++))
    else
        info "✓ Service removed"
    fi
    
    # Check for processes
    if pgrep -x cloudflared >/dev/null; then
        warning "cloudflared process still running"
        ((issues++))
    else
        info "✓ No running processes"
    fi
    
    echo
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ Cloudflared successfully removed!${NC}"
    else
        echo -e "${YELLOW}${BOLD}⚠ Removal complete with $issues warning(s)${NC}"
        echo -e "${YELLOW}You may need to manually check for remaining files${NC}"
    fi
}

# Main execution
main() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔════════════════════════════════════════════════╗"
    echo "║                                                ║"
    echo "║       CLOUDFLARED REMOVAL SCRIPT               ║"
    echo "║                                                ║"
    echo "╚════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
    
    check_root
    detect_os
    
    echo
    warning "This will completely remove Cloudflared from your system"
    read -p "Continue? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Removal cancelled"
        exit 0
    fi
    
    echo
    stop_cloudflared_service
    echo
    remove_cloudflared_package
    echo
    remove_cloudflared_repos
    echo
    remove_cloudflared_configs
    echo
    remove_cloudflared_binary
    echo
    final_cleanup
    echo
    verify_removal
    
    echo
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}           REMOVAL COMPLETE                     ${NC}"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════${NC}"
    echo
}

main "$@"
