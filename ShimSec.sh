#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/shimsec"
BIN_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/shimsec"

print_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║            ShimSec Suite v1.0          ║${NC}"
    echo -e "${BLUE}║     Made with <3 By lyrix on discord   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        DISTRO=$DISTRIB_ID
    else
        DISTRO=$(uname -s)
    fi
    echo $DISTRO | tr '[:upper:]' '[:lower:]'
}

install_dependencies() {
    local distro=$1
    log_info "Installing dependencies for $distro..."
    
    case $distro in
        ubuntu|debian|linuxmint|pop)
            sudo apt update
            sudo apt install -y curl wget git openvpn wireguard-tools tor privoxy squid dante-server shadowsocks-libev python3 python3-pip
            ;;
        fedora|rhel|centos)
            sudo dnf install -y curl wget git openvpn wireguard-tools tor privoxy squid dante-server shadowsocks-libev python3 python3-pip
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm curl wget git openvpn wireguard-tools tor privoxy squid dante-server shadowsocks python python-pip
            ;;
        opensuse*)
            sudo zypper install -y curl wget git openvpn wireguard-tools tor privoxy squid dante-server shadowsocks-libev python3 python3-pip
            ;;
        *)
            log_warn "Unknown distro. Attempting generic installation..."
            ;;
    esac
    
    log_success "Dependencies installed"
}

setup_directories() {
    log_info "Setting up directories..."
    sudo mkdir -p "$INSTALL_DIR"/{configs,logs,scripts}
    mkdir -p "$CONFIG_DIR"
    sudo chmod 755 "$INSTALL_DIR"
    log_success "Directories created"
}

install_protonvpn() {
    log_info "Installing ProtonVPN CLI..."
    pip3 install --user protonvpn-cli
    log_success "ProtonVPN CLI installed"
}

install_mullvad() {
    log_info "Installing Mullvad VPN..."
    wget -qO- https://mullvad.net/download/app/deb/latest | sudo tee /tmp/mullvad.deb > /dev/null 2>&1 || log_warn "Mullvad download may have issues, continuing..."
    log_info "Mullvad ready (manual setup required)"
}

configure_tor() {
    log_info "Configuring Tor..."
    sudo systemctl enable tor 2>/dev/null || true
    sudo systemctl start tor 2>/dev/null || true
    echo -e "SOCKSPort 9050\nControlPort 9051" | sudo tee -a /etc/tor/torrc > /dev/null
    sudo systemctl restart tor 2>/dev/null || true
    log_success "Tor configured on port 9050"
}

configure_privoxy() {
    log_info "Configuring Privoxy..."
    echo "forward-socks5 / 127.0.0.1:9050 ." | sudo tee -a /etc/privoxy/config > /dev/null
    sudo systemctl enable privoxy 2>/dev/null || true
    sudo systemctl start privoxy 2>/dev/null || true
    log_success "Privoxy configured on port 8118"
}

configure_squid() {
    log_info "Configuring Squid proxy..."
    sudo bash -c 'cat > /etc/squid/squid.conf << EOF
http_port 3128
acl localnet src 127.0.0.1
http_access allow localnet
http_access deny all
EOF'
    sudo systemctl enable squid 2>/dev/null || true
    sudo systemctl restart squid 2>/dev/null || true
    log_success "Squid proxy configured on port 3128"
}

create_custom_getty() {
    log_info "Creating ShimSecDM..."
    
    # Create the custom getty wrapper
    sudo tee "$INSTALL_DIR/scripts/shimsec-login.sh" > /dev/null << 'EOF'
#!/bin/bash

# ShimSecDM

CYAN='\033[0;36m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[1;35m'
NC='\033[0m'

display_banner() {
    clear
    echo -e "${CYAN}"
    cat << "BANNER"
   _____ __    _            _____           
  / ___// /_  (_)___ ___   / ___/___  _____
  \__ \/ __ \/ / __ `__ \  \__ \/ _ \/ ___/
 ___/ / / / / / / / / / / ___/ /  __/ /__  
/____/_/ /_/_/_/ /_/ /_/ /____/\___/\___/  
                                            
BANNER
    echo -e "${NC}"
    echo -e "${GREEN}Welcome to a more private experience...${NC}"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

perform_login() {
    while true; do
        display_banner
        
        # Get username
        echo -ne "${MAGENTA}Username: ${NC}"
        read username
        
        if [ -z "$username" ]; then
            continue
        fi
        
        # Get password (hidden input)
        echo -ne "${MAGENTA}Password: ${NC}"
        read -s password
        echo ""
        
        # Attempt authentication
        echo "$password" | su - "$username" -c "true" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            # Successful login
            clear
            display_banner
            echo -e "${GREEN}✓ Login successful!${NC}"
            echo ""
            
            # Show active services
            if systemctl is-active tor &>/dev/null || systemctl is-active privoxy &>/dev/null; then
                echo -e "${YELLOW}Active Privacy Services:${NC}"
                systemctl is-active tor &>/dev/null && echo -e "  ${GREEN}✓${NC} Tor (SOCKS5 @ 127.0.0.1:9050)"
                systemctl is-active privoxy &>/dev/null && echo -e "  ${GREEN}✓${NC} Privoxy (HTTP @ 127.0.0.1:8118)"
                systemctl is-active squid &>/dev/null && echo -e "  ${GREEN}✓${NC} Squid (HTTP @ 127.0.0.1:3128)"
                echo ""
            fi
            
            echo -e "${CYAN}Type 'shimsec --help' for privacy tools${NC}"
            echo ""
            
            sleep 2
            
            # Start user shell
            exec su - "$username"
        else
            # Failed login
            echo ""
            echo -e "${RED}✗ Login incorrect${NC}"
            sleep 2
        fi
    done
}

# Main execution
perform_login
EOF

    sudo chmod +x "$INSTALL_DIR/scripts/shimsec-login.sh"
    
    # Disable graphical display managers
    log_info "Disabling graphical display managers..."
    
    # Detect and disable common display managers
    for dm in gdm gdm3 lightdm sddm lxdm xdm kdm; do
        if systemctl is-enabled $dm &>/dev/null; then
            sudo systemctl disable $dm 2>/dev/null || true
            sudo systemctl stop $dm 2>/dev/null || true
            log_info "Disabled $dm"
        fi
    done
    
    # Override getty on tty1 with our custom login
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
    sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-$INSTALL_DIR/scripts/shimsec-login.sh
Type=idle
StandardInput=tty
StandardOutput=tty
Restart=always
EOF

    # Set default target to multi-user (text mode)
    sudo systemctl set-default multi-user.target 2>/dev/null || true
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    log_success "ShimSec TTY Display Manager installed!"
}

create_shimsec_command() {
    log_info "Creating ShimSec CLI tool..."
    
    sudo tee "$BIN_DIR/shimsec" > /dev/null << 'EOF'
#!/bin/bash

CONFIG_DIR="$HOME/.config/shimsec"
STATE_FILE="$CONFIG_DIR/state.conf"

show_help() {
    echo "ShimSec - Privacy Tool Manager"
    echo ""
    echo "Usage: shimsec [COMMAND] [SERVICE]"
    echo ""
    echo "Commands:"
    echo "  --on <service>     Enable a VPN/proxy service"
    echo "  --off <service>    Disable a VPN/proxy service"
    echo "  --status           Show status of all services"
    echo "  --list             List available services"
    echo "  --help             Show this help message"
    echo ""
    echo "Available Services:"
    echo "  tor                Tor SOCKS proxy (port 9050)"
    echo "  privoxy            Privoxy HTTP proxy (port 8118)"
    echo "  squid              Squid HTTP proxy (port 3128)"
    echo "  protonvpn          ProtonVPN CLI"
    echo "  openvpn            OpenVPN"
    echo ""
}

service_on() {
    case $1 in
        tor)
            sudo systemctl start tor
            echo "Tor proxy enabled on 127.0.0.1:9050"
            ;;
        privoxy)
            sudo systemctl start privoxy
            echo "Privoxy enabled on 127.0.0.1:8118"
            ;;
        squid)
            sudo systemctl start squid
            echo "Squid proxy enabled on 127.0.0.1:3128"
            ;;
        protonvpn)
            protonvpn connect -f
            echo "ProtonVPN connected"
            ;;
        openvpn)
            echo "Please specify OpenVPN config: sudo openvpn --config /path/to/config.ovpn"
            ;;
        *)
            echo "Unknown service: $1"
            show_help
            exit 1
            ;;
    esac
}

service_off() {
    case $1 in
        tor)
            sudo systemctl stop tor
            echo "Tor proxy disabled"
            ;;
        privoxy)
            sudo systemctl stop privoxy
            echo "Privoxy disabled"
            ;;
        squid)
            sudo systemctl stop squid
            echo "Squid proxy disabled"
            ;;
        protonvpn)
            protonvpn disconnect
            echo "ProtonVPN disconnected"
            ;;
        openvpn)
            sudo killall openvpn 2>/dev/null
            echo "OpenVPN stopped"
            ;;
        *)
            echo "Unknown service: $1"
            show_help
            exit 1
            ;;
    esac
}

show_status() {
    echo "ShimSec Service Status:"
    echo "======================"
    
    systemctl is-active tor &>/dev/null && echo "Tor: ACTIVE" || echo "Tor: INACTIVE"
    systemctl is-active privoxy &>/dev/null && echo "Privoxy: ACTIVE" || echo "Privoxy: INACTIVE"
    systemctl is-active squid &>/dev/null && echo "Squid: ACTIVE" || echo "Squid: INACTIVE"
    
    if pgrep -x openvpn > /dev/null; then
        echo "OpenVPN: ACTIVE"
    else
        echo "OpenVPN: INACTIVE"
    fi
    
    if command -v protonvpn &> /dev/null; then
        protonvpn status 2>/dev/null | grep -q "Connected" && echo "ProtonVPN: ACTIVE" || echo "ProtonVPN: INACTIVE"
    fi
}

case "$1" in
    --on)
        service_on "$2"
        ;;
    --off)
        service_off "$2"
        ;;
    --status)
        show_status
        ;;
    --list)
        echo "Available services: tor, privoxy, squid, protonvpn, openvpn"
        ;;
    --help|*)
        show_help
        ;;
esac
EOF

    sudo chmod +x "$BIN_DIR/shimsec"
    log_success "ShimSec CLI tool created"
}

show_menu() {
    print_header
    echo -e "${GREEN}Select components to install:${NC}"
    echo ""
    echo "1) Install All (Recommended)"
    echo "2) Tor + Privoxy (Onion routing + HTTP proxy)"
    echo "3) Squid Proxy (HTTP caching proxy)"
    echo "4) ProtonVPN CLI"
    echo "5) OpenVPN (manual config required)"
    echo "6) Custom Selection"
    echo "7) Exit"
    echo ""
    read -p "Enter choice [1-7]: " choice
    
    case $choice in
        1)
            install_all=true
            ;;
        2)
            configure_tor
            configure_privoxy
            ;;
        3)
            configure_squid
            ;;
        4)
            install_protonvpn
            ;;
        5)
            log_info "OpenVPN installed. Add configs to /etc/openvpn/"
            ;;
        6)
            custom_install
            ;;
        7)
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

custom_install() {
    read -p "Install Tor? (y/n): " tor
    read -p "Install Privoxy? (y/n): " privoxy
    read -p "Install Squid? (y/n): " squid
    read -p "Install ProtonVPN? (y/n): " proton
    
    [[ $tor == "y" ]] && configure_tor
    [[ $privoxy == "y" ]] && configure_privoxy
    [[ $squid == "y" ]] && configure_squid
    [[ $proton == "y" ]] && install_protonvpn
}

main() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run with sudo"
        exit 1
    fi
    
    print_header
    
    DISTRO=$(detect_distro)
    log_info "Detected distro: $DISTRO"
    
    setup_directories
    install_dependencies "$DISTRO"
    
    show_menu
    
    if [ "$install_all" = true ]; then
        configure_tor
        configure_privoxy
        configure_squid
        install_protonvpn
    fi
    
    create_shimsec_command
    create_custom_getty
    
    echo ""
    log_success "ShimSec installation complete!"
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  shimsec --on tor        # Enable Tor"
    echo "  shimsec --off tor       # Disable Tor"
    echo "  shimsec --status        # Check status"
    echo "  shimsec --help          # Show help"
    echo ""
    echo -e "${YELLOW}Note: ProtonVPN requires account setup${NC}"
    echo -e "${YELLOW}Run: protonvpn init${NC}"
    echo ""
    echo -e "${GREEN}ShimSecDM is now active!${NC}"
    echo -e "${RED}IMPORTANT: Graphical display managers have been disabled.${NC}"
    echo -e "${YELLOW}It would be nice for you to reboot now.${NC}"
    echo ""
    echo -e "${BLUE}To restore graphical login later:${NC}"
    echo -e "  sudo systemctl set-default graphical.target"
    echo -e "  sudo systemctl enable gdm3  # or lightdm, sddm, etc."
}

mainA
