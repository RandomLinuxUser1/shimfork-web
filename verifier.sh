#!/bin/bash
set -euo pipefail

# Disable echo for clean output
stty -echo 2>/dev/null || true

# Color definitions
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[1;32m'
readonly RED='\033[1;31m'
readonly BLUE='\033[1;34m'
readonly CYAN='\033[1;36m'
readonly MAGENTA='\033[1;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly RESET='\033[0m'

# Symbols
readonly SYM_CHECK="✓"
readonly SYM_FAIL="✗"
readonly SYM_WAIT="◌"
readonly SYM_ARROW="→"

# Get terminal dimensions
COLS=$(tput cols 2>/dev/null || echo 80)
LINES=$(tput lines 2>/dev/null || echo 24)

# Cleanup on exit
cleanup() {
    stty echo 2>/dev/null || true
    tput cnorm 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Hide cursor
tput civis 2>/dev/null || true

# Center text
center() {
    local text="$1"
    local color="${2:-$RESET}"
    local text_len=${#text}
    local padding=$(( (COLS - text_len) / 2 ))
    printf "%*s%b%s%b\n" $padding "" "$color" "$text" "$RESET"
}

# Progress bar
progress_bar() {
    local percent=$1
    local width=40
    local filled=$(( width * percent / 100 ))
    local empty=$(( width - filled ))
    
    printf "  ["
    printf "%b" "$GREEN"
    printf "%${filled}s" | tr ' ' '█'
    printf "%b" "$DIM"
    printf "%${empty}s" | tr ' ' '░'
    printf "%b" "$RESET"
    printf "] %3d%%\r" "$percent"
}

# Animated status line
status_line() {
    local desc="$1"
    local color="$2"
    local symbol="$3"
    local max_desc_len=50
    
    # Truncate description if too long
    if [ ${#desc} -gt $max_desc_len ]; then
        desc="${desc:0:$max_desc_len-3}..."
    fi
    
    printf "  %-${max_desc_len}s %b[%s]%b\n" "$desc" "$color" "$symbol" "$RESET"
}

# Spinner animation
spinner() {
    local pid=$1
    local desc="$2"
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        printf "\r  %b%s%b %-50s" "$CYAN" "${frames[$i]}" "$RESET" "$desc"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
    printf "\r%*s\r" $COLS ""
}

# Check function with improved visuals
check() {
    local desc="$1"
    local cmd="$2"
    local critical="${3:-true}"
    
    # Show pending status
    status_line "$desc" "$YELLOW" "$SYM_WAIT"
    
    # Run check in background for timeout support
    if timeout 5 bash -c "$cmd" >/dev/null 2>&1; then
        # Move cursor up and show success
        printf "\033[F"
        status_line "$desc" "$GREEN" "$SYM_CHECK"
        return 0
    else
        # Move cursor up and show failure
        printf "\033[F"
        status_line "$desc" "$RED" "$SYM_FAIL"
        
        if [ "$critical" = "true" ]; then
            echo
            echo -e "${RED}${BOLD}╔════════════════════════════════════════════════╗${RESET}"
            echo -e "${RED}${BOLD}║     CRITICAL VERIFICATION FAILURE              ║${RESET}"
            echo -e "${RED}${BOLD}╚════════════════════════════════════════════════╝${RESET}"
            echo
            echo -e "${RED}Failed check:${RESET} $desc"
            echo
            echo -e "${YELLOW}Troubleshooting:${RESET}"
            echo "  • Check system logs: journalctl -xb"
            echo "  • Verify service status: systemctl status"
            echo "  • Run diagnostics: shimfork verify"
            echo
            echo -e "${DIM}Press Enter to drop to emergency shell...${RESET}"
            read -r
            cleanup
            exec /bin/bash
        fi
        return 1
    fi
}

# Detect display manager
detect_dm() {
    for dm in gdm gdm3 sddm lightdm lxdm xdm; do
        if systemctl is-enabled "$dm" >/dev/null 2>&1; then
            echo "$dm"
            return 0
        fi
    done
    return 1
}

# Get system info
get_system_info() {
    local hostname
    local kernel
    local uptime_sec
    
    hostname=$(hostname 2>/dev/null || echo "unknown")
    kernel=$(uname -r 2>/dev/null || echo "unknown")
    uptime_sec=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo "0")
    
    echo "$hostname|$kernel|$uptime_sec"
}

# Draw header with ASCII art
draw_header() {
    clear
    echo
    center "╔════════════════════════════════════════════════╗" "$CYAN"
    center "║                                                ║" "$CYAN"
    center "║         █▀ █ █ █ █▀▄▀█ █▀▀ █▀█ █▀█ █▄▀        ║" "$CYAN"
    center "║         ▄█ █▀█ █ █ ▀ █ █▀  █▄█ █▀▄ █ █        ║" "$CYAN"
    center "║                                                ║" "$CYAN"
    center "║          SYSTEM VERIFICATION SUITE             ║" "$CYAN"
    center "║                                                ║" "$CYAN"
    center "╚════════════════════════════════════════════════╝" "$CYAN"
    echo
    
    # System info
    IFS='|' read -r hostname kernel uptime_sec <<< "$(get_system_info)"
    local uptime_min=$(( uptime_sec / 60 ))
    
    echo -e "  ${DIM}Hostname:${RESET} $hostname"
    echo -e "  ${DIM}Kernel:${RESET}   $kernel"
    echo -e "  ${DIM}Uptime:${RESET}   ${uptime_min}m"
    echo
}

# Draw section header
section_header() {
    local title="$1"
    echo -e "${BOLD}${BLUE}━━━ $title ━━━${RESET}"
    echo
}

# Main verification process
main() {
    local total_checks=8
    local current_check=0
    local failed_checks=0
    
    draw_header
    
    # Core System Checks
    section_header "Core System"
    
    ((current_check++))
    check "Root filesystem integrity" "mountpoint -q /" || ((failed_checks++))
    
    ((current_check++))
    check "Shimfork components installed" "[ -d /usr/lib/shimfork ] && [ -x /usr/bin/shimfork ]" || ((failed_checks++))
    
    ((current_check++))
    check "System time synchronized" "timedatectl status | grep -q 'synchronized: yes'" false || true
    
    echo
    
    # Network Checks
    section_header "Network Services"
    
    ((current_check++))
    check "NetworkManager service" "systemctl is-active NetworkManager || systemctl is-active network" || ((failed_checks++))
    
    ((current_check++))
    check "DNS resolution" "nslookup cloudflare.com >/dev/null 2>&1 || host cloudflare.com >/dev/null 2>&1" false || true
    
    ((current_check++))
    check "Internet connectivity" "ping -c1 -W3 1.1.1.1 || ping -c1 -W3 8.8.8.8" || ((failed_checks++))
    
    echo
    
    # Privacy Services
    section_header "Privacy & Security"
    
    ((current_check++))
    check "Tor service" "systemctl is-active tor" || ((failed_checks++))
    
    ((current_check++))
    check "I2P service" "systemctl is-active i2p || systemctl is-active i2pd" || ((failed_checks++))
    
    echo
    
    # Display Manager Check
    section_header "Display Manager"
    
    if DM=$(detect_dm); then
        check "Display manager ($DM)" "systemctl status $DM >/dev/null 2>&1"
        
        echo
        echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════╗${RESET}"
        echo -e "${GREEN}${BOLD}║     ALL VERIFICATIONS PASSED                   ║${RESET}"
        echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════╝${RESET}"
        echo
        
        if [ $failed_checks -gt 0 ]; then
            echo -e "${YELLOW}Warning: $failed_checks non-critical check(s) failed${RESET}"
            echo
        fi
        
        # Countdown to display manager start
        echo -e "${DIM}Starting $DM in...${RESET}"
        for i in 3 2 1; do
            echo -ne "\r  ${CYAN}${BOLD}$i${RESET}"
            sleep 1
        done
        echo
        
        cleanup
        systemctl start "$DM"
    else
        status_line "Display manager" "$RED" "$SYM_FAIL"
        echo
        echo -e "${YELLOW}${BOLD}╔════════════════════════════════════════════════╗${RESET}"
        echo -e "${YELLOW}${BOLD}║     NO DISPLAY MANAGER DETECTED                ║${RESET}"
        echo -e "${YELLOW}${BOLD}╚════════════════════════════════════════════════╝${RESET}"
        echo
        echo -e "${YELLOW}Starting console login...${RESET}"
        sleep 2
        cleanup
        exec /bin/bash --login
    fi
}

# Run main function
main
