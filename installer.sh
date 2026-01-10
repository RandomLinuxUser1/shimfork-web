#!/bin/bash
set -e

BASE_URL="https://shimfork.pages.dev"

if [ "$EUID" -ne 0 ]; then
  echo "[!] Run as root"
  exit 1
fi

clear
echo "======================================"
echo "        SHIMFORK INSTALLER"
echo "======================================"
echo

detect_dm() {
  for dm in gdm sddm lightdm xdm; do
    if systemctl is-enabled "$dm" >/dev/null 2>&1; then
      echo "$dm"
      return
    fi
  done
  echo "none"
}

EXISTING_DM="$(detect_dm)"

if [ "$EXISTING_DM" != "none" ]; then
  echo "[+] Desktop environment detected ($EXISTING_DM)"
  INSTALL_DESKTOP=false
else
  echo "[!] No desktop environment detected"
  INSTALL_DESKTOP=true
fi

if [ "$INSTALL_DESKTOP" = true ]; then
  echo
  echo "Select a desktop environment:"
  echo "0) Skip desktop installation"
  echo "1) XFCE (recommended)"
  echo "2) KDE Plasma"
  echo "3) LXQt"
  read -p "> " DE_CHOICE

  case "$DE_CHOICE" in
    0)
      INSTALL_DESKTOP=false
      ;;
    1)
      DESKTOP_PKGS="xfce4 xfce4-goodies"
      DM="lightdm"
      ;;
    2)
      DESKTOP_PKGS="kde-standard"
      DM="sddm"
      ;;
    3)
      DESKTOP_PKGS="lxqt"
      DM="lightdm"
      ;;
    *)
      echo "Invalid selection"
      exit 1
      ;;
  esac
fi

echo
echo "[*] Updating system"
apt update

echo "[*] Installing base packages"
apt install -y wget curl sudo git ca-certificates systemd dbus network-manager

if [ "$INSTALL_DESKTOP" = true ]; then
  echo "[*] Installing desktop environment"
  apt install -y $DESKTOP_PKGS $DM
  systemctl enable "$DM"
else
  echo "[*] Desktop installation skipped"
fi

echo "[*] Installing privacy tools"
apt install -y tor cloudflared wireguard-tools
systemctl enable --now tor
systemctl enable --now cloudflared

echo "[*] Installing Shimfork verifier"
mkdir -p /usr/lib/shimfork
wget -O /usr/lib/shimfork/verifier.sh "$BASE_URL/verifier.sh"
chmod +x /usr/lib/shimfork/verifier.sh

cat << 'EOF' > /etc/systemd/system/shimfork-verify.service
[Unit]
Description=Shimfork Boot Verification
Before=display-manager.service
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/lib/shimfork/verifier.sh
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > /usr/bin/shimfork
#!/bin/bash

case "$1" in
  status)
    echo "Shimfork status:"
    systemctl is-active tor >/dev/null && echo "Tor: running" || echo "Tor: stopped"
    systemctl is-active cloudflared >/dev/null && echo "Cloudflare Tunnel: running" || echo "Cloudflare Tunnel: stopped"
    systemctl is-enabled shimfork-verify.service >/dev/null && \
      echo "Boot verifier: enabled" || echo "Boot verifier: disabled"
    ;;
  start)
    systemctl enable "$2" --now
    ;;
  stop)
    systemctl disable "$2" --now
    ;;
  enable-verify)
    systemctl enable shimfork-verify.service
    ;;
  disable-verify)
    systemctl disable shimfork-verify.service
    ;;
  verify)
    /usr/lib/shimfork/verifier.sh
    ;;
  *)
    echo "Usage:"
    echo "  shimfork status"
    echo "  shimfork start tor"
    echo "  shimfork stop tor"
    echo "  shimfork start cloudflared"
    echo "  shimfork stop cloudflared"
    echo "  shimfork enable-verify"
    echo "  shimfork disable-verify"
    echo "  shimfork verify"
    ;;
esac
EOF

chmod +x /usr/bin/shimfork

echo
echo "======================================"
echo "      SHIMFORK INSTALL COMPLETE"
echo "======================================"
echo
echo "Available commands:"
echo "  shimfork status"
echo "  shimfork start tor"
echo "  shimfork stop tor"
echo "  shimfork start cloudflared"
echo "  shimfork stop cloudflared"
echo "  shimfork enable-verify"
echo "  shimfork disable-verify"
echo "  shimfork verify"
echo
echo "Reboot recommended."
echo "======================================"
