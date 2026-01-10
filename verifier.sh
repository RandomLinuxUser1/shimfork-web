#!/bin/bash
clear
stty -echo

yellow='\033[1;33m'
green='\033[1;32m'
red='\033[1;31m'
reset='\033[0m'

cols=$(tput cols)
center() {
  printf "%*s\n" $(((${#1}+$cols)/2)) "$1"
}

status_line() {
  printf " %-45s %b[%s]%b\n" "$1" "$2" "$3" "$reset"
}

check() {
  status_line "$1" "$yellow" "?"
  sleep 0.5
  if eval "$2" >/dev/null 2>&1; then
    printf "\033[F"
    status_line "$1" "$green" "+"
  else
    printf "\033[F"
    status_line "$1" "$red" "!"
    echo
    echo -e "${red}Verification failed. Dropping to shell.${reset}"
    stty echo
    exec /bin/bash
  fi
}

detect_dm() {
  for dm in gdm sddm lightdm xdm; do
    if systemctl is-enabled "$dm" >/dev/null 2>&1; then
      echo "$dm"
      return
    fi
  done
  echo ""
}

echo
center "=============================="
center " SHIMFORK SYSTEM VERIFIER "
center "=============================="
echo
sleep 0.5

check "Root filesystem mounted" "mountpoint -q /"
check "Shimfork core present" "[ -d /usr/lib/shimfork ]"
check "NetworkManager active" "systemctl is-active NetworkManager"
check "Internet reachable" "ping -c1 1.1.1.1"
check "Tor service running" "systemctl is-active tor"
check "cloudflared running" "systemctl is-active cloudflared"

DM="$(detect_dm)"

if [ -n "$DM" ]; then
  check "Display manager detected ($DM)" "systemctl status $DM"
  echo
  center "Verification complete"
  sleep 1
  stty echo
  systemctl start "$DM"
else
  echo
  status_line "Display manager detected" "$red" "!"
  echo
  echo -e "${red}No display manager installed.${reset}"
  stty echo
  exec /bin/bash
fi
