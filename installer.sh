#!/bin/bash
set -euo pipefail

# Configuration
readonly BASE_URL="https://shimfork.pages.dev"
readonly SCRIPT_VERSION="2.0"
readonly LOG_FILE="/var/log/shimfork-install.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    log "ERROR: $*"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
    log "WARNING: $*"
}

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
    log "INFO: $*"
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
        OS_VERSION="$VERSION_ID"
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
            error "Unsupported OS: $OS"
            ;;
    esac

    info "Detected OS: $OS $OS_VERSION (Package manager: $PKG_MANAGER)"
}

# Detect existing display manager
detect_dm() {
    for dm in gdm gdm3 sddm lightdm xdm lxdm; do
        if systemctl is-enabled "$dm" >/dev/null 2>&1 || systemctl is-active "$dm" >/dev/null 2>&1; then
            echo "$dm"
            return
        fi
    done
    echo "none"
}

# Install packages based on package manager
install_packages() {
    local packages="$*"
    
    case "$PKG_MANAGER" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $packages
            ;;
        dnf)
            dnf install -y $packages
            ;;
        pacman)
            pacman -S --noconfirm $packages
            ;;
    esac
}

# Update system
update_system() {
    info "Updating system packages..."
    
    case "$PKG_MANAGER" in
        apt)
            apt-get update
            apt-get upgrade -y
            ;;
        dnf)
            dnf update -y
            ;;
        pacman)
            pacman -Syu --noconfirm
            ;;
    esac
}

# Select and install desktop environment
setup_desktop() {
    local existing_dm
    existing_dm="$(detect_dm)"

    if [ "$existing_dm" != "none" ]; then
        info "Desktop environment detected: $existing_dm"
        read -p "Skip desktop installation? [Y/n]: " skip_desktop
        if [[ "$skip_desktop" =~ ^[Nn]$ ]]; then
            INSTALL_DESKTOP=true
        else
            INSTALL_DESKTOP=false
            return
        fi
    else
        warning "No desktop environment detected"
        INSTALL_DESKTOP=true
    fi

    if [ "$INSTALL_DESKTOP" = true ]; then
        echo
        echo "Select a desktop environment:"
        echo "0) Skip desktop installation"
        echo "1) XFCE (lightweight, recommended)"
        echo "2) KDE Plasma (feature-rich)"
        echo "3) GNOME (modern)"
        echo "4) LXQt (very lightweight)"
        read -p "> " de_choice

        case "$de_choice" in
            0)
                INSTALL_DESKTOP=false
                return
                ;;
            1)
                case "$PKG_MANAGER" in
                    apt) DESKTOP_PKGS="xfce4 xfce4-goodies"; DM="lightdm" ;;
                    dnf) DESKTOP_PKGS="@xfce-desktop-environment"; DM="lightdm" ;;
                    pacman) DESKTOP_PKGS="xfce4 xfce4-goodies"; DM="lightdm" ;;
                esac
                ;;
            2)
                case "$PKG_MANAGER" in
                    apt) DESKTOP_PKGS="kde-standard"; DM="sddm" ;;
                    dnf) DESKTOP_PKGS="@kde-desktop-environment"; DM="sddm" ;;
                    pacman) DESKTOP_PKGS="plasma-meta"; DM="sddm" ;;
                esac
                ;;
            3)
                case "$PKG_MANAGER" in
                    apt) DESKTOP_PKGS="gnome-core"; DM="gdm3" ;;
                    dnf) DESKTOP_PKGS="@gnome-desktop"; DM="gdm" ;;
                    pacman) DESKTOP_PKGS="gnome"; DM="gdm" ;;
                esac
                ;;
            4)
                case "$PKG_MANAGER" in
                    apt) DESKTOP_PKGS="lxqt"; DM="sddm" ;;
                    dnf) DESKTOP_PKGS="@lxqt-desktop-environment"; DM="sddm" ;;
                    pacman) DESKTOP_PKGS="lxqt"; DM="sddm" ;;
                esac
                ;;
            *)
                error "Invalid selection"
                ;;
        esac

        info "Installing desktop environment..."
        install_packages $DESKTOP_PKGS $DM
        systemctl enable "$DM" || warning "Failed to enable display manager"
    fi
}

# Install base packages
install_base_packages() {
    info "Installing base packages..."
    
    case "$PKG_MANAGER" in
        apt)
            install_packages wget curl sudo git ca-certificates systemd dbus \
                network-manager gnupg lsb-release
            ;;
        dnf)
            install_packages wget curl sudo git ca-certificates systemd dbus \
                NetworkManager gnupg
            ;;
        pacman)
            install_packages wget curl sudo git ca-certificates systemd dbus \
                networkmanager gnupg
            ;;
    esac
}

# Install privacy tools
install_privacy_tools() {
    info "Installing privacy tools..."
    
    case "$PKG_MANAGER" in
        apt)
            install_packages tor wireguard-tools
            ;;
        dnf)
            install_packages tor wireguard-tools
            ;;
        pacman)
            install_packages tor wireguard-tools
            ;;
    esac

    systemctl enable tor || warning "Failed to enable Tor"
    systemctl start tor || warning "Failed to start Tor"
}

# Install Cloudflared
install_cloudflared() {
    info "Installing Cloudflared..."
    
    case "$PKG_MANAGER" in
        apt)
            if [ ! -f /usr/share/keyrings/cloudflare-archive-keyring.gpg ]; then
                curl -fsSL https://pkg.cloudflare.com/pubkey.gpg | \
                    gpg --dearmor -o /usr/share/keyrings/cloudflare-archive-keyring.gpg
            fi
            
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-archive-keyring.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | \
                tee /etc/apt/sources.list.d/cloudflared.list
            
            apt-get update
            install_packages cloudflared
            ;;
        dnf)
            dnf copr enable -y cloudflare/cloudflared || \
                warning "Failed to add Cloudflared repo"
            install_packages cloudflared
            ;;
        pacman)
            install_packages cloudflared
            ;;
    esac

    systemctl enable cloudflared || warning "Failed to enable Cloudflared"
}

# Setup Shimfork verifier
setup_verifier() {
    info "Setting up Shimfork verifier..."
    
    mkdir -p /usr/lib/shimfork
    
    if ! wget -q -O /usr/lib/shimfork/verifier.sh "$BASE_URL/verifier.sh"; then
        warning "Failed to download verifier script"
        return
    fi
    
    chmod +x /usr/lib/shimfork/verifier.sh

    cat > /etc/systemd/system/shimfork-verify.service << 'EOF'
[Unit]
Description=Shimfork Boot Verification
Before=display-manager.service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/lib/shimfork/verifier.sh
StandardInput=tty
StandardOutput=journal+console
StandardError=journal+console
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

# Create shimfork command
create_shimfork_command() {
    info "Creating shimfork command..."
    
    cat > /usr/bin/shimfork << 'EOF'
#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_status() {
    echo -e "${GREEN}=== Shimfork Status ===${NC}"
    
    # Tor status
    if systemctl is-active tor >/dev/null 2>&1; then
        echo -e "Tor:                ${GREEN}running${NC}"
    else
        echo -e "Tor:                ${RED}stopped${NC}"
    fi
    
    # Cloudflared status
    if systemctl is-active cloudflared >/dev/null 2>&1; then
        echo -e "Cloudflare Tunnel:  ${GREEN}running${NC}"
    else
        echo -e "Cloudflare Tunnel:  ${RED}stopped${NC}"
    fi
    
    # Boot verifier status
    if systemctl is-enabled shimfork-verify.service >/dev/null 2>&1; then
        echo -e "Boot verifier:      ${GREEN}enabled${NC}"
    else
        echo -e "Boot verifier:      ${YELLOW}disabled${NC}"
    fi
}

case "${1:-}" in
    status)
        show_status
        ;;
    start)
        if [ -z "${2:-}" ]; then
            echo "Usage: shimfork start [tor|cloudflared]"
            exit 1
        fi
        sudo systemctl start "$2"
        sudo systemctl enable "$2"
        echo -e "${GREEN}Started and enabled $2${NC}"
        ;;
    stop)
        if [ -z "${2:-}" ]; then
            echo "Usage: shimfork stop [tor|cloudflared]"
            exit 1
        fi
        sudo systemctl stop "$2"
        echo -e "${YELLOW}Stopped $2${NC}"
        ;;
    enable-verify)
        sudo systemctl enable shimfork-verify.service
        echo -e "${GREEN}Boot verifier enabled${NC}"
        ;;
    disable-verify)
        sudo systemctl disable shimfork-verify.service
        echo -e "${YELLOW}Boot verifier disabled${NC}"
        ;;
    verify)
        sudo /usr/lib/shimfork/verifier.sh
        ;;
    version)
        echo "Shimfork CLI v2.0"
        ;;
    *)
        echo "Shimfork - Privacy and Security Tools Manager"
        echo
        echo "Usage:"
        echo "  shimfork status              Show service status"
        echo "  shimfork start <service>     Start and enable service"
        echo "  shimfork stop <service>      Stop service"
        echo "  shimfork enable-verify       Enable boot verification"
        echo "  shimfork disable-verify      Disable boot verification"
        echo "  shimfork verify              Run verifier manually"
        echo "  shimfork version             Show version"
        echo
        echo "Services: tor, cloudflared"
        ;;
esac
EOF

    chmod +x /usr/bin/shimfork
}

# Main installation flow
main() {
    clear
    echo "======================================"
    echo "    SHIMFORK INSTALLER v$SCRIPT_VERSION"
    echo "======================================"
    echo

    check_root
    detect_os
    
    read -p "Continue with installation? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "Installation cancelled"
        exit 0
    fi

    update_system
    install_base_packages
    setup_desktop
    install_privacy_tools
    install_cloudflared
    setup_verifier
    create_shimfork_command

    echo
    echo "======================================"
    echo "   SHIMFORK INSTALLATION COMPLETE"
    echo "======================================"
    echo
    info "Available commands:"
    echo "  shimfork status"
    echo "  shimfork start tor|cloudflared"
    echo "  shimfork stop tor|cloudflared"
    echo "  shimfork enable-verify"
    echo "  shimfork disable-verify"
    echo "  shimfork verify"
    echo
    warning "A system reboot is recommended."
    echo "======================================"
    
    read -p "Reboot now? [y/N]: " reboot_confirm
    if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
        info "Rebooting system..."
        sleep 2
        reboot
    fi
}

main "$@"
